// Copyright Dave Verwer, Sven A. Schmidt, and other contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ArgumentParser
import CleverBird
import Foundation


public struct GenerateDescriptions: AsyncParsableCommand {
    @Option(name: .shortAndLong, parsing: .upToNextOption)
    var packageIDs: [PackageID]

    @Option(name: .long)
    var githubApiToken: String

    @Option(name: .long)
    var openAIApiToken: String

    @Option(name: .shortAndLong)
    var outdir: String = "./descriptions"

    public func run() async throws {
        let openAIAPIConnection = OpenAIAPIConnection(apiKey: openAIApiToken)

        if FileManager.default.fileExists(atPath: outdir) == false {
            try FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)
        }

        for packageID in packageIDs {
            let filepath = outdir + "/" + packageID.descriptionFilename
            if FileManager.default.fileExists(atPath: filepath) {
                print("Description exists at path '\(filepath)', skipping generation ...")
            } else {
                print("Generating description: \(packageID) ...")

                let readme = try await Github.fetchReadme(packageID: packageID, githubApiToken: githubApiToken)
                print("Readme length:", readme.count)
                print("Message length:", readme.trimmedToMaxMessage.count)

                let chatThread = ChatThread(connection: openAIAPIConnection,
                                            model: .gpt35Turbo)
                    .addSystemMessage(Self.systemPrompt)
                    .addUserMessage(readme.trimmedToMaxMessage)
                let result = try await chatThread.complete()
                if let content = result .content {
                    print("Result:", content)
                    try Data(content.utf8).write(to: URL(filePath: filepath))
                } else {
                    print("No content returned.")
                }
            }
        }
    }


    public init() { }
}


extension GenerateDescriptions {
    static var systemPrompt: String {
        """
        You are a technical editor that summarises Markdown input.
        You are an expert in the Swift programming language.
        All input will be README files from library packages.
        Your task is to summarise and determine the library’s purpose.
        It is more important to be brief than to summarise everything.
        It is CRUCIAL to strictly adhere to a maximum of 30 words in all generated content, without exceptions.
        NEVER begin the paragraph with “The purpose of” or “Summary:”.
        NEVER include "is a library", "is a package", or "is a tool".
        NEVER include details of installation or compatibility.
        NEVER include license information.
        NEVER include code listings.
        NEVER include any of these words: iOS, macOS, tvOS, watchOS, Linux, CocoaPods, Carthage, Swift Package Manager, SPM.
        """
    }
}


private extension String {
    var trimmedToMaxMessage: Self {
        return String(prefix(OpenAI.maxMessageLength))
    }
}


enum OpenAI {
    static let maxTokens = 4097.0
    static let charactersPerToken = 2.4
    static let completionMaxLength = 256.0
    static var maxMessageLength: Int { Int(maxTokens * charactersPerToken - completionMaxLength) }
}
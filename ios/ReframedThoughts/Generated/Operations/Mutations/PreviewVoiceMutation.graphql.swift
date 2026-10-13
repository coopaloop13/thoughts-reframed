// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct PreviewVoiceMutation: GraphQLMutation {
    static let operationName: String = "PreviewVoice"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation PreviewVoice { previewVoice }"#
      ))

    public init() {}

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("previewVoice", String.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        PreviewVoiceMutation.Data.self
      ] }

      var previewVoice: String { __data["previewVoice"] }
    }
  }

}
// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct EnrollVoiceMutation: GraphQLMutation {
    static let operationName: String = "EnrollVoice"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation EnrollVoice($sample: File!, $referenceText: String!) { enrollVoice(sample: $sample, referenceText: $referenceText) { __typename id hasVoice } }"#
      ))

    public var sample: File
    public var referenceText: String

    public init(
      sample: File,
      referenceText: String
    ) {
      self.sample = sample
      self.referenceText = referenceText
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "sample": sample,
      "referenceText": referenceText
    ] }

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("enrollVoice", EnrollVoice.self, arguments: [
          "sample": .variable("sample"),
          "referenceText": .variable("referenceText")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        EnrollVoiceMutation.Data.self
      ] }

      var enrollVoice: EnrollVoice { __data["enrollVoice"] }

      /// EnrollVoice
      nonisolated struct EnrollVoice: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.User }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", GQL.ID.self),
          .field("hasVoice", Bool.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          EnrollVoiceMutation.Data.EnrollVoice.self
        ] }

        var id: GQL.ID { __data["id"] }
        var hasVoice: Bool { __data["hasVoice"] }
      }
    }
  }

}
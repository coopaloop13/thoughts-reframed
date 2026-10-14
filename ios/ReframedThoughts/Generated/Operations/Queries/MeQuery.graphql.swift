// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct MeQuery: GraphQLQuery {
    static let operationName: String = "Me"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Me { me { __typename id hasVoice profile } }"#
      ))

    public init() {}

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("me", Me.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        MeQuery.Data.self
      ] }

      var me: Me { __data["me"] }

      /// Me
      nonisolated struct Me: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.User }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", GQL.ID.self),
          .field("hasVoice", Bool.self),
          .field("profile", String?.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          MeQuery.Data.Me.self
        ] }

        var id: GQL.ID { __data["id"] }
        var hasVoice: Bool { __data["hasVoice"] }
        var profile: String? { __data["profile"] }
      }
    }
  }

}
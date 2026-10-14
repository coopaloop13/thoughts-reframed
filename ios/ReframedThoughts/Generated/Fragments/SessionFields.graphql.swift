// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct SessionFields: GQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment SessionFields on Session { __typename id status transcript reframedText audioUrl error createdAt crisis turns { __typename ...TurnFields } }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Session }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", GQL.ID.self),
      .field("status", GraphQLEnum<GQL.SessionStatus>.self),
      .field("transcript", String?.self),
      .field("reframedText", String?.self),
      .field("audioUrl", String?.self),
      .field("error", String?.self),
      .field("createdAt", GQL.DateTime.self),
      .field("crisis", Bool.self),
      .field("turns", [Turn].self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SessionFields.self
    ] }

    var id: GQL.ID { __data["id"] }
    var status: GraphQLEnum<GQL.SessionStatus> { __data["status"] }
    var transcript: String? { __data["transcript"] }
    var reframedText: String? { __data["reframedText"] }
    var audioUrl: String? { __data["audioUrl"] }
    var error: String? { __data["error"] }
    var createdAt: GQL.DateTime { __data["createdAt"] }
    var crisis: Bool { __data["crisis"] }
    var turns: [Turn] { __data["turns"] }

    /// Turn
    nonisolated struct Turn: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Turn }
      static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(TurnFields.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SessionFields.Turn.self,
        TurnFields.self
      ] }

      var id: GQL.ID { __data["id"] }
      var status: GraphQLEnum<GQL.SessionStatus> { __data["status"] }
      var userText: String? { __data["userText"] }
      var agentText: String? { __data["agentText"] }
      var audioUrl: String? { __data["audioUrl"] }
      var crisis: Bool { __data["crisis"] }
      var closing: Bool { __data["closing"] }
      var error: String? { __data["error"] }
      var createdAt: GQL.DateTime { __data["createdAt"] }

      struct Fragments: FragmentContainer {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        var turnFields: TurnFields { _toFragment() }
      }
    }
  }

}
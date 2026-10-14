// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct TurnFields: GQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment TurnFields on Turn { __typename id status userText agentText audioUrl crisis closing error createdAt }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Turn }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", GQL.ID.self),
      .field("status", GraphQLEnum<GQL.SessionStatus>.self),
      .field("userText", String?.self),
      .field("agentText", String?.self),
      .field("audioUrl", String?.self),
      .field("crisis", Bool.self),
      .field("closing", Bool.self),
      .field("error", String?.self),
      .field("createdAt", GQL.DateTime.self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
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
  }

}
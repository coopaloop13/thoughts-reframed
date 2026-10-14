// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

nonisolated protocol GQL_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == GQL.SchemaMetadata {}

nonisolated protocol GQL_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == GQL.SchemaMetadata {}

nonisolated protocol GQL_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == GQL.SchemaMetadata {}

nonisolated protocol GQL_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == GQL.SchemaMetadata {}

extension GQL {
  typealias SelectionSet = GQL_SelectionSet

  typealias InlineFragment = GQL_InlineFragment

  typealias MutableSelectionSet = GQL_MutableSelectionSet

  typealias MutableInlineFragment = GQL_MutableInlineFragment

  nonisolated enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

    private static let objectTypeMap: [String: ApolloAPI.Object] = [
      "AuthPayload": GQL.Objects.AuthPayload,
      "Mutation": GQL.Objects.Mutation,
      "Query": GQL.Objects.Query,
      "Session": GQL.Objects.Session,
      "Subscription": GQL.Objects.Subscription,
      "Turn": GQL.Objects.Turn,
      "User": GQL.Objects.User
    ]

    static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
      objectTypeMap[typename]
    }
  }

  nonisolated enum Objects {}
  nonisolated enum Interfaces {}
  nonisolated enum Unions {}

}
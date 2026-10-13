// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct SignInWithAppleMutation: GraphQLMutation {
    static let operationName: String = "SignInWithApple"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SignInWithApple($identityToken: String!) { signInWithApple(identityToken: $identityToken) { __typename token user { __typename id hasVoice } } }"#
      ))

    public var identityToken: String

    public init(identityToken: String) {
      self.identityToken = identityToken
    }

    @_spi(Unsafe) public var __variables: Variables? { ["identityToken": identityToken] }

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("signInWithApple", SignInWithApple.self, arguments: ["identityToken": .variable("identityToken")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SignInWithAppleMutation.Data.self
      ] }

      var signInWithApple: SignInWithApple { __data["signInWithApple"] }

      /// SignInWithApple
      nonisolated struct SignInWithApple: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.AuthPayload }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("token", String.self),
          .field("user", User.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SignInWithAppleMutation.Data.SignInWithApple.self
        ] }

        var token: String { __data["token"] }
        var user: User { __data["user"] }

        /// SignInWithApple.User
        nonisolated struct User: GQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { GQL.Objects.User }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("id", GQL.ID.self),
            .field("hasVoice", Bool.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            SignInWithAppleMutation.Data.SignInWithApple.User.self
          ] }

          var id: GQL.ID { __data["id"] }
          var hasVoice: Bool { __data["hasVoice"] }
        }
      }
    }
  }

}
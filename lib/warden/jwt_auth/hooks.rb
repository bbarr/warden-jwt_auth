# frozen_string_literal: true

module Warden
  module JWTAuth
    # Warden hooks
    class Hooks
      include JWTAuth::Import['mappings', 'dispatch_requests', 'aud_header']

      # `env` key where JWT is added
      PREPARED_TOKEN_ENV_KEY = 'warden-jwt_auth.token'

      # Adds a token for the signed in user to the request `env` if current path
      # and verb match with configuration. This will be picked up later on by a
      # rack middleware which will add it to the response headers.
      #
      # @see https://github.com/hassox/warden/wiki/Callbacks
      def self.after_set_user(user, auth, opts)
        new.send(:prepare_token, user, auth, opts)
      end

      # Sign out a JWT scope if it comes from the session unless it is an HTML
      # request
      #
      # If a user is meant to be authenticated via JWT, then if it is fetched
      # from the session during an API request it must be something not intended
      # to happen and a security threat.
      #
      # Workaround until https://github.com/hassox/warden/pull/118 is fixed
      def self.after_fetch(_user, auth, opts)
        new.send(:logout_scope, auth, opts)
      end

      private

      def prepare_token(user, auth, opts)
        env = auth.env
        scope = opts[:scope]
        return unless token_should_be_added?(scope, env)
        add_token_to_env(user, scope, env)
      end

      # :reek:FeatureEnvy
      def logout_scope(auth, opts)
        env = auth.env
        scope = opts[:scope]
        return if !jwt_scope?(scope) || EnvHelper.no_api_request?(env)
        auth.logout(scope)
      end

      def token_should_be_added?(scope, env)
        path_info = EnvHelper.path_info(env)
        method = EnvHelper.request_method(env)
        jwt_scope?(scope) && request_matches?(path_info, method)
      end

      # :reek:ManualDispatch
      # :reek:UtilityFunction
      def add_token_to_env(user, scope, env)
        aud = EnvHelper.aud_header(env)
        token, payload = UserEncoder.new.call(user, scope, aud)
        user.on_jwt_dispatch(token, payload) if user.respond_to?(:on_jwt_dispatch)
        env[PREPARED_TOKEN_ENV_KEY] = token
      end

      def jwt_scope?(scope)
        jwt_scopes = mappings.keys
        jwt_scopes.include?(scope)
      end

      # :reek:ControlParameter
      def request_matches?(path_info, method)
        dispatch_requests.each do |tuple|
          dispatch_method, dispatch_path = tuple
          return true if path_info.match(dispatch_path) &&
                         method == dispatch_method
        end
        false
      end
    end
  end
end

Warden::Manager.after_set_user do |user, auth, opts|
  Warden::JWTAuth::Hooks.after_set_user(user, auth, opts)
end

Warden::Manager.after_fetch do |user, auth, opts|
  Warden::JWTAuth::Hooks.after_fetch(user, auth, opts)
end

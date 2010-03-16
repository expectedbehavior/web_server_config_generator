# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_no_webconfig_app_session',
  :secret      => '9ef906148a2d4ccb8125d1c807b1cc6dd0009dbe1e38dec0278ff3605f574dd324d4827fadb6c26a94a22b8e24bd601a5dc60b357bf89a4fa85a726ff556e056'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store

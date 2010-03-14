# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_sub_uri_app_foo_session',
  :secret      => '5efa0ce44d84137b23386fb716939d411287dababa02d8934ec331fb59b1f9b5ca24fb3e05f31ef2fea376a95fc21257dd227a1f7361e5ebe8f55b1d517ad35d'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store

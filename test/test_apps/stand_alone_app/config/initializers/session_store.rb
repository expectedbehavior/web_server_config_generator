# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_stand_alone_app_session',
  :secret      => '3a8a07d22658ac7161d1515db745296f62a402f5fd4ec310c0b9902a1d110b35873162525e3ff73ea9a35d9b1f695657f1696cafc1c772e5b82e0ab7cfca9838'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store

# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_sub_uri_app_bar_session',
  :secret      => '567657207096224533a75eb1438851ffc593e14cbeabacc52b7f10203a6cb83170196b1403885e27a3a93626a7a78004c9d81ba9f994d9529b3114e32381bb4e'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store

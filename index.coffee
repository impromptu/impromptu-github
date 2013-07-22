async = require 'async'
read = require 'read'
request = require 'request'

module.exports = (Impromptu, register, github) ->
  class ImpromptuGitHubError extends Impromptu.Error

  register 'token',
    update: (done) ->
      async.waterfall [
        (fn) ->
          read prompt: 'What is your GitHub username?', (err, username) ->
            fn err, username

        (username, fn) ->
          read prompt: 'What is your GitHub password?', silent: true, (err, password) ->
            fn err, username, password

        (username, password, fn) ->
          request.post
            url: 'https://api.github.com/authorizations'
            auth:
              user: username
              pass: password
            body:
              scopes: ['repo']
              note: "Impromptu GitHub Module"
            json: true
          , (err, response, body) ->
            return fn err, null if err
            return fn err, body.token if body.token

            if body.message
              message = "An error occurred while creating your GitHub token: #{body.message}"
            else
              message = "An unknown error occurred while creating your GitHub token."

            console.log message
            fn new ImpromptuGitHubError message, null

      ], done

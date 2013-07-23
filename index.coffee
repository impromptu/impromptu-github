async = require 'async'
read = require 'read'
request = require 'request'

module.exports = (Impromptu, register, github) ->
  git = @module.require 'impromptu-git'
  rGitHubUrl = /^(?:git@github.com:|https:\/\/github.com\/)([^\/]+)\/([^\/]+)\.git/

  class ImpromptuGitHubError extends Impromptu.Error

  register '_parseRemoteUrl',
    update: (done) ->
      git.remoteUrl (err, url) ->
        return done err if err
        done err, url.match rGitHubUrl

  register 'isGitHub',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, !!results

  register 'remoteUser',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results && results[1]

  register 'remoteRepo',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results && results[2]

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

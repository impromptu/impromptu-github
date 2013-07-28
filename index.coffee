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

        results = url.match rGitHubUrl
        return done err, null unless results

        done err,
          user: results[1]
          repo: results[2]

  register 'isGitHub',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, !!results

  register 'remoteUser',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results?.user

  register 'remoteRepo',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results?.repo

  register 'token',
    cache: 'global'
    run: (fn) ->
      @get (err, token) =>
        return fn err, token if token
        @_setThenGet fn

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

            fn new ImpromptuGitHubError message, null

      ], done

  requestGitHub = (path, options, done) ->
    unless done
      done = options
      options = null

    github.token (err, token) ->
      return done err if err

      options ?= {}
      options.uri = "https://api.github.com/#{path}"
      options.json = true
      options.qs ?= {}
      options.qs.access_token = token
      request options, done

  register 'ci',
    cache: 'repository'
    expire: 300
    update: (done) ->
      git.remoteBranch (err, branch) ->
        return done err, branch if err or not branch

        async.parallel [
          github._parseRemoteUrl,
          git.branch
        ], (err, results) ->
          [remote, branch] = results
          requestGitHub "repos/#{remote.user}/#{remote.repo}/statuses/#{branch}", (err, response, body) ->
            return done err, '' unless body and body.length
            done err, body[0].state

  register 'pullRequest',
    cache: 'repository'
    expire: 300
    update: (done) ->
      git.remoteBranch (err, branch) ->
        return done err, branch if err or not branch

        async.parallel [
          github._parseRemoteUrl,
          git.branch
        ], (err, results) ->
          [remote, branch] = results
          requestGitHub "repos/#{remote.user}/#{remote.repo}/pulls",
            qs:
              head: "#{remote.user}:#{branch}"
          , (err, response, body) ->
            return done err, '' unless body and body.length
            done err, body[0].number


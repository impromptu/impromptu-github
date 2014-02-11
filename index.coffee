async = require 'async'
read = require 'read'
request = require 'request'

module.exports = (Impromptu, register, github) ->
  git = @module.require 'impromptu-git'
  rGitHubUrl = /^(?:git@github.com:|https:\/\/github.com\/)([^\/]+)\/([^\/]+)\.git/

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
    update: (done) ->
      process.env.IMPROMPTU_GITHUB_TOKEN

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


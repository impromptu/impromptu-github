impromptu = require 'impromptu'
git = require 'impromptu-git'

async = require 'async'
read = require 'read'
request = require 'request'

module.exports = impromptu.plugin.create (github) ->
  rGitHubUrl = /^(?:git@github.com:|https:\/\/github.com\/)([^\/]+)\/([^\/]+)\.git/

  github.register '_parseRemoteUrl',
    update: (done) ->
      git.remoteUrl (err, url) ->
        return done err if err

        results = url.match rGitHubUrl
        return done err, null unless results

        done err,
          user: results[1]
          repo: results[2]

  github.register 'isGitHub',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, !!results

  github.register 'remoteUser',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results?.user

  github.register 'remoteRepo',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results?.repo

  github.register 'token',
    update: ->
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
      options.headers = {
        'User-Agent': 'Impromptu-GitHub'
      }
      request options, done

  github.register 'ci',
    cache: 'repository'
    expire: 60
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

  github.register 'pullRequest',
    cache: 'repository'
    expire: 60
    update: (done) ->
      async.parallel [
        github._parseRemoteUrl,
        git.remoteBranch,
        git.branch
      ], (err, results) ->
        return done err, null if err

        [remote, remoteBranchWithOrigin, localBranch] = results
        remoteBranch = remoteBranchWithOrigin.replace(/^[^\/]+\//, '')
        branch = remoteBranch || localBranch

        requestGitHub "repos/#{remote.user}/#{remote.repo}/pulls",
          qs:
            head: "#{remote.user}:#{branch}"
        , (err, response, body) ->
          return done err, '' unless body and body.length
          done err, body[0].number


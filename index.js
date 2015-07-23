var impromptu = require('impromptu')
var git = require('impromptu-git')
var async = require('async')
var read = require('read')
var request = require('request')

module.exports = impromptu.plugin.create(function (github) {
  var rGitHubUrl = /^(?:git@github.com:|https:\/\/github.com\/)([^\/]+)\/([^\/]+)\.git/

  github.register('_parseRemoteUrl', {
    update: function (done) {
      git.remoteUrl(function (err, url) {
        if (err) {
          done(err)
          return
        }

        var results = url.match(rGitHubUrl)
        if (!results) {
          done(err, null)
          return
        }

        done(err, {
          user: results[1],
          repo: results[2]
        })
      })
    }
  })

  github.register('isGitHub', {
    update: function (done) {
      github._parseRemoteUrl(function (err, results) {
        done(err, !!results)
      })
    }
  })

  github.register('remoteUser', {
    update: function (done) {
      github._parseRemoteUrl(function (err, results) {
        done(err, results != null ? results.user : null)
      })
    }
  })

  github.register('remoteRepo', {
    update: function (done) {
      github._parseRemoteUrl(function (err, results) {
        done(err, results != null ? results.repo : null)
      })
    }
  })

  github.register('token', {
    update: function () {
      return process.env.IMPROMPTU_GITHUB_TOKEN
    }
  })

  var requestGitHub = function (path, options, done) {
    if (!done) {
      done = options
      options = null
    }

    github.token(function (err, token) {
      if (err || !token) {
        done(err)
        return
      }

      options = options || {}
      options.uri = 'https://api.github.com/' + path
      options.json = true

      if (options.qs == null) options.qs = {}
      options.qs.access_token = token

      options.headers = {
        'User-Agent': 'Impromptu-GitHub'
      }

      request(options, done)
    })
  }

  github.register('ci', {
    cache: 'repository',
    expire: 60,
    update: function (done) {
      git.remoteBranch(function (err, branch) {
        if (err || !branch) {
          done(err, branch)
          return
        }

        async.parallel([github._parseRemoteUrl, git.branch], function (err, results) {
          var remote = results[0]
          branch = results[1]

          requestGitHub('repos/' + remote.user + '/' + remote.repo + '/statuses/' + branch,
              function (err, response, body) {
                if (!(body && body.length)) {
                  done(err, '')
                  return
                }
                done(err, body[0].state)
              })
        })
      })
    }
  })

  var requestFirstPullRequest = function (remote, branch, state, done) {
    requestGitHub('repos/' + remote.user + '/' + remote.repo + '/pulls', {
      qs: {
        head: remote.user + ':' + branch,
        state: state === 'closed' ? 'closed' : 'open'
      }
    }, function (err, response, body) {
      if (body && body.length) {
        done(err, body[0])
      } else {
        done(err, null)
      }
    })
  }

  github.register('_pullRequest', {
    cache: 'repository',
    expire: 60,
    update: function (done) {
      async.parallel([github._parseRemoteUrl, git.remoteBranch, git.branch], function (err, results) {
        if (err) {
          done(err, null)
          return
        }

        var remote = results[0]
        var remoteBranchWithOrigin = results[1]
        var localBranch = results[2]
        var remoteBranch = remoteBranchWithOrigin.replace(/^[^\/]+\//, '')
        var branch = remoteBranch || localBranch

        requestFirstPullRequest(remote, branch, 'open', function (err, pullRequest) {
          if (err) {
            done(err, null)
            return
          }

          // Return the first open pull request we find.
          if (pullRequest) {
            done(err, pullRequest)
            return
          }

          // If we didn't find an open pull request, search for closed ones.
          requestFirstPullRequest(remote, branch, 'closed', function (err, pullRequest) {
            done(err, pullRequest || null)
          })
        })
      })
    }
  })

  github.register('pullRequestNumber', {
    update: function (done) {
      github._pullRequest(function (err, pullRequest) {
        done(err, pullRequest ? pullRequest.number : null)
      })
    }
  })

  github.register('pullRequestState', {
    update: function (done) {
      github._pullRequest(function (err, pullRequest) {
        done(err, pullRequest ? pullRequest.state : null)
      })
    }
  })
})

## CI Comment

CI Comment is a Sinatra application that posts messages from Jenkins to GitHub pull requests. After adding a new message, CI Comment will remove any previous automatic messages on that pull request.

- Runs on [OpenShift](https://openshift.redhat.com/)

`key.txt` contains the GitHub token.

`secret.txt` contains the secret used to authenticate requests to CI Comment.

Example request

> curl -d "secret=a&comment=test_0&repo=q-a/qa-test&issue=2" http://0.0.0.0:3000/comment

CI Comment is released under the [Apache License Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.txt).

--

- `bundle install`
- `gem install passenger --no-rdoc --no-ri`

Run locally with `passenger start`

---

## OpenShift

Add Gemfile.lock, key.txt, and secret.txt for OpenShift deploy.

--

[Issue Comments API](http://developer.github.com/v3/issues/comments/)

- Get token [for command line use](https://help.github.com/articles/creating-an-oauth-token-for-command-line-use)

> curl -u 'userName' -d '{"scopes":["repo"],"note":"Command line"}' https://api.github.com/authorizations

- Tokens can be revoked [here](https://github.com/settings/applications)
- Test that the OAuth token works

Replace `ownerName`, `repoName`, and `issueNumber`.

> curl -H "Authorization: token 0000000000000000000000000000000000000000" -d '{"body":"Comment from CURL"}' https://api.github.com/repos/ownerName/repoName/issues/issueNumber/comments

## Using with Leeroy

[Leeroy](https://github.com/litl/leeroy) provides Jenkins integration with GitHub pull requests. Once Leeroy is configured, the following can be used to setup automatic notifications to CI Comment on a linux node.

## Pre Build Groovy

Replace `org/repo` with the real org and repo. Update COMMENT to include your Jenkins test job.

```groovy
// GITHUB_URL
// GIT_SHA1

String GHURL = GITHUB_URL == null ? "" : GITHUB_URL.replace("https://github.com/org/repo/","")
String SHA = GIT_SHA1

SHA = SHA.substring(0,6)
String COMMENT = " test-job [# " + BUILD_NUMBER + "](https://example.com/jenkins/job/test-job/" + BUILD_NUMBER + "/) "+ SHA
String PULL_NUMBER = GITHUB_URL == null ? "" : GITHUB_URL.replace("https://github.com/org/repo/pull/","")

// Skip posting if we're on master
String skip = SHA == "master"

return [GROOVY: SHA + " " + GHURL, C: COMMENT, N: PULL_NUMBER, SKIP: skip ]
```

Set the build name using build name plugin.

```
#${BUILD_NUMBER} ${ENV,var="GROOVY"}
```

The following two post build steps must be the last post build actions. For example the cucumber publish post build step will mark a build as failed. It's important to run Groovy post build after the build has been marked by cucumber or it may report success for a failed build.

## Groovy Post Build

```groovy
import hudson.model.ParametersAction;
import hudson.model.StringParameterValue;

String result = manager.build.getResult().toString().toLowerCase()

if(manager.logContains(".*marked build as failure.*") || result.contains("fail")) {
  result = "\\:x\\: failed"
} else if (result.contains("success")) {
  result = "\\:white_check_mark\\: " + result
}

def act = new ParametersAction([
  new StringParameterValue("R", result)
])

Thread.currentThread().executable.addAction(act)
```

## Shell Post Build

Use curl to communicate with CI Comment on OpenShift. Note that it's important to use https.

```bash
# $R result, $C comment, $N pull request number
echo "SKIP value: $SKIP"
if [ "$SKIP" = "false" ]; then
  curl -d "secret=secretValue&sha=$GIT_SHA1&comment=$R $C&repo=org/repo&issue=$N" https://appname-opencloud.rhcloud.com/comment
fi
```

Alternatively just post directly to the GitHub API. Replace `org/repo` with the actual org and repo.

```bash
# Replace 000s with the real token.
# $R result, $C comment, $N pull request number
echo "SKIP value: $SKIP"
if [ "$SKIP" = "false" ]; then
  curl -H "Authorization: token 0000000000000000000000000000000000000000" -d "{\"body\":\"$R $C\"}" https://api.github.com/repos/org/repo/issues/$N/comments
fi
```

## Ext Email Plugin

Cancel email if not on master.

```groovy
def env = Thread.currentThread()?.executable.parent.builds[0].properties.get("envVars");
def skip = env.get("SKIP");
cancel = false;

// If skip is true then we're on master.
// If skip is false then it's a pull request
// so cancel the email.
if (skip == "false") {
  cancel = true;
}

// Don't remove. E-mail will not be canceled without this.
// https://github.com/jenkinsci/email-ext-plugin/commit/5fa24b49277c865e63148b40d109d3df7c1a5db0
// The email has not been canceled unless the following is recorded in the log:
// "Email sending was cancelled by user script."
// I'm aware cancel = cancel should not fix the bug of emails not being canceled but it does...
cancel = cancel;
```
# Deconst Content Repository addition

This is a terrible, hacky Ruby script to automate the addition of content repositories to a Deconst cluster. It:

 * Clones the repository
 * Locates the Sphinx content
 * Generates `_deconst.json` and `.travis.yml` files
 * Issues a new API key
 * Encrypts the API key and Slack token into `.travis.yml`
 * Adds a Travis build badge to the `README.md` file

It also makes a ton of assumptions and will basically fall over if any of them are violated, but hey.

## Usage

First-time setup, assuming a reasonable Ruby environment:

```bash
gem install octokit httparty
cp env.example.sh env.sh
${EDITOR} env.sh
source env.sh

mkdir ~/autoadd
```

Then to set up a repository in `rackerlabs/`:

```bash
ruby submit.rb docs-cloud-images
```

If something goes wrong, you can revoke the issued API key with:

```bash
ruby revoke.rb <api-key>
```

A pull request will be submitted to the destination repository. Merge it to start :shipit: :zap:

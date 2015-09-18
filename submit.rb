#!/bin/env ruby

require 'find'
require 'fileutils'
require 'json'
require 'octokit'
require 'httparty'

@repo_name = ARGV[0]
@repo_git_upstream = "git@github.com:rackerlabs/#{@repo_name}.git"
@content_id_base = "https://github.com/rackerlabs/#{@repo_name}/"
@admin_apikey = ENV['ADMIN_APIKEY']
@github_access_token = ENV['GITHUB_TOKEN']
@slack_travis_token = ENV['SLACK_TOKEN']

def sh command
  system command
  unless $?.success?
    raise RuntimeError.new("Command [#{command}] exited with [#{$?.exitstatus}]")
  end
end

def validate!
  missing = []

  missing << '- ADMIN_APIKEY' unless @admin_apikey
  missing << '- GITHUB_TOKEN' unless @github_access_token
  missing << '- SLACK_TOKEN' unless @slack_travis_token

  unless missing.empty?
    $stderr.puts "Missing required configuration settings:"
    missing.each { |e| $stderr.puts e }
    exit 1
  end
end

def clone_repo
  if File.directory? @repo_name
    puts "deleting existing repository"
    FileUtils.rm_rf @repo_name
  end

  puts "cloning repository"
  sh "git clone --origin upstream #{@repo_git_upstream}"
  Dir.chdir @repo_name

  puts "forking repository"
  Octokit.fork("rackerlabs/#{@repo_name}")

  until Octokit.repository? "#{Octokit.user.login}/#{@repo_name}"
    puts "..."
    sleep 5
  end
  puts "fork complete"

  sh "git remote add origin git@github.com:#{Octokit.user.login}/#{@repo_name}.git"
  sh "git checkout -b deconst-build"
end

def find_root
  conf_path = Find.find('.').detect { |path| File.basename(path) == "conf.py" }
  File.dirname(conf_path).gsub(/^\.\//, '')
end

def template_deconst subdir
  File.write("#{subdir}/_deconst.json", <<EOF)
{
  "contentIDBase": "#{@content_id_base}"
}
EOF
end

def template_script_cibuild subdir
  FileUtils.mkdir_p "script"
  File.write("script/cibuild", <<EOF)
#!/bin/bash
#
# Used by Travis to submit content to Nexus production

set -euo pipefail

if [ "${TRAVIS_PULL_REQUEST}" = "false" ] && [ "${TRAVIS_BRANCH}" = "master" ]; then
  echo "Submitting content to production."
  export CONTENT_STORE_URL=https://developer.rackspace.com:9000/
  export CONTENT_STORE_APIKEY=${PROD1}${PROD2}${PROD3}
else
  echo "Not submitting ${TRAVIS_BRANCH} anywhere."
fi

cd #{subdir}
deconst-preparer-sphinx
EOF
  File.chmod(0755, "script/cibuild")
end

def template_travis
  File.write(".travis.yml", <<EOF)
language: python
python:
- '3.4'
sudo: false
install:
- pip install -e git+https://github.com/deconst/preparer-sphinx.git#egg=deconstrst
script:
- script/cibuild
EOF
end

def issue_apikey
  puts "Issuing a new API key"
  resp = HTTParty.post "https://developer.rackspace.com:9000/keys",
    query: { "named" => @repo_name },
    headers: { "Authorization" => "deconst apikey=\"#{@admin_apikey}\"" }
  apikey = resp.parsed_response["apikey"]

  puts "Issued API key: [#{apikey}]"

  {
    "PROD1" => apikey[0..79],
    "PROD2" => apikey[80..159],
    "PROD3" => apikey[160..-1]
  }
end

def setup_travis key_parts
  puts "Setting up the build"
  sh "travis login --github-token #{@github_access_token}"
  sh "travis enable -r rackerlabs/#{@repo_name}"

  key_parts.each_pair do |name, value|
    puts "Encrypting #{name}"
    sh "travis encrypt -r rackerlabs/#{@repo_name} --add env.global #{name}=#{value}"
  end

  puts "Encrypting Slack token"
  sh "travis encrypt -r rackerlabs/#{@repo_name} --add notifications.slack #{@slack_travis_token}"
end

def readme_badge
  puts "Adding a Travis build badge to the README"

  badge_md = "[![Build Status](https://travis-ci.org/rackerlabs/#{@repo_name}.svg?branch=master)](https://travis-ci.org/rackerlabs/#{@repo_name})"

  unless File.exists? 'README.md'
    File.write('README.md', <<EOM)
#{@repo_name}
---

#{badge_md}
EOM
    return
  end

  current = File.read('README.md')
  return if current.include?(badge_md)

  modified = current.sub(/(#[^#\n]+)/, "\\1\n\n#{badge_md}\n")
  File.write('README.md', modified)
end

def submit_pr
  puts "committing and pushing"
  sh 'git add .'
  sh 'git commit -m "Configure Deconst build"'
  sh 'git push -u origin deconst-build'

  puts "creating pull request"
  pr = Octokit.create_pull_request "rackerlabs/#{@repo_name}",
    "master", "#{Octokit.user.login}:deconst-build",
    "Configure Travis build", <<EOM
Configure this repository's Travis build. Once merged, all content committed to the master branch of this repository will be submitted to [developer.rackspace.com](https://developer.rackspace.com/).

Note that the content won't be *routed* and accessible until we submit a follow-on pull request to [the control repository](https://github.com/rackerlabs/nexus-control).
EOM
  puts "Submitted pull request: #{pr.html_url}"
end

def main
  clone_repo
  subdir = find_root
  puts "Content is in the subdirectory: [#{subdir}]"

  template_deconst subdir
  template_script_cibuild subdir
  template_travis

  key_parts = issue_apikey
  setup_travis key_parts
  readme_badge

  submit_pr

  puts "All set up ✨"
end

validate!

Octokit.configure do |c|
  c.access_token = @github_access_token
end

Dir.chdir "#{ENV['HOME']}/autoadd/"

puts "Adding content repository: #{@repo_name}"
puts "- content ID base: #{@content_id_base}"
puts "- git clone URL: #{@repo_git_upstream}"
puts "- authenticated to GitHub as: #{Octokit.user.login}"
puts "- pwd: #{Dir.pwd}"

main

# Development Setup Instructions

## 0. Quick Summary

### Linux Workstation Setup

    sudo apt-get install git curl default-libmysqlclient-dev default-jdk
    export JAVA_HOME=/usr/lib/jvm/default-java
    export LD_LIBRARY_PATH=$JAVA_HOME/lib:$JAVA_HOME/lib/server
    
    git clone git@github.com:trustthevote/Rocky-OVR.git rocky
    curl -L https://get.rvm.io | bash -s stable
    source ~/.bash_profile
    rvm install $(cat .ruby-version)
    
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
    nvm install --lts
    nvm use --lts

    cd rocky
    gem install bundler
    gem install ffi -- --disable-system-libffi
    bundle install
    
    vim .env # add variable settings as needed (see below)

### App Deployment

    cap <environment> deploy:setup
    cap <environment> deploy

## 1. Create real versions of the .example files

### a. Ruby version management

The `rocky` application is setup assuming you're using RVM. The ruby version and
gemset name are stored in the `.ruby-version` and `.ruby-gemset` files which
should set your RVM environment automatically. If you're using a ruby version
manager other than RVM you'll need to make changes to the deploy process.

### b. Customizing files

In the `rocky` application replace all the `*.example` files with real ones.

The following files contain sensitive data like passwords so we don't commit them to
version control. You'll of course need to fill in the actual useful data in the
real files. See the contents of the example files for details on how they're
used.

  * `config/database.yml`
  * `config/newrelic.yml`
  * `db/bootstrap/partners.yml`
  * `.env.[environment_name]` for example, .env.staging or .env.production
  
There are a number of files used by the `rails_config` gem - `config/settings.yml`
and all the files under `config/settings/`. These are checked into source
control and should be reviewed for accuracy. They don't contain sensitive
information, but have values that are specific to the environment and instance
of the `rocky` application being deployed.

For API registration calls to work correctly the value of `pdf_hostname` (see
config/settings.yml and config/settings/<env>.yml) should be set to the host
name of the server that has to be put in the PDF URLs.

For a complete custom deployment, many of the files in `app/assets` and
`config/locales` should be customized to your brand.

### c. Getting the app to run locally

Once RVM is installed (and the appropriate ruby version and gemset have been set
up) and all of the example .yml and .env files have been turned into the real
versions, run:

    $ gem install bundler
    $ bundle install
  
If the database hasn't been created yet, set that up by running

    $ bundle exec rake db:create db:schema:load db:migrate db:bootstrap

## 2. Configure deploy scripts

The `rocky` application is set up to be deployed using capistrano with
multistage. The repository contains the generic `config/deploy.rb` file with
the main set of procedures for a deployment and there are a number of
environment-specific files in `config/deploy/`. These files just contain a few
settings which reference environment variables. These variables need to be set
in your `.env` file (which only needs to exist on your development machine, or
wherever you run your cap scripts from). See `.env.example` for a list of what
values need to be specified.


## 3a. AWS Deploys

To watch a particular codedeploy, run on the ec2 server:

    tail -n1000 -f  /opt/codedeploy-agent/deployment-root/deployment-logs/codedeploy-agent-deployments.log

## 3. Configure servers

The current deploy process for all environments assumes a separate web and
utility server. The web server is configured to handle web requests and the
utility server runs PDF generation, cron jobs (for cleanup tasks) and hosts the
PDF files once generated.

The apache setup on the webserver should pass through to the utility server for
all requests for generated PDF files.

### a. ssh

To simplify the initial deploy process, both the web and utility servers should
be configured to allow ssh connections to github without needing a user to
manually accept github as a known host. This can be done by adding the following
into the deployment users' `~/.ssh/config` file on both the web and util servers.

    Host github.com
      User git
      StrictHostKeyChecking no
      BatchMode yes
      IdentityFile /home/rocky/.ssh/id_rsa

### b. Installation requirements

Install dependencies for CentOS/RHEL:

    yum install apr-devel apr-util-devel gcc-c++ httpd-devel ImageMagick-devel \
      libcurl-devel libxslt-devel libyaml-devel mysql-devel perl-DBD-MySQL \
      perl-DBI perl-XML-Simple zlib-devel

### c. Apache

The capistrano deploy:setup task makes an assumption that the server will be
using rvm, apache2 and passenger. The apache config file for the site should be
created assuming certain path values for gems and modules installed by
RVM/gem/passenger during the cap deploy tasks.

The parts of these paths depend on:

* ruby version (currently 1.9.3-p125, specified in `.ruby-version`)
* gemset name (currently rocky4, specified in `.ruby-gemset`)
* passenger version (currently 3.0.19, specified in `config/deploy.rb` in the :install_passenger task)

If the gemset, ruby version or passenger version changes the paths in the apache
config file will need to change. This should not be a common occurrence.

### d. cron

There are two cron jobs running on the utility server that should be located in
`/etc/cron.d`. One redacts sensitive data from abandoned registrations and the
other removes old pdfs from the file system after 15 days. (Or however many days
is indicated in the configuration)

    */10 * * * * rocky /var/www/register.rockthevote.com/rocky/current/script/cron_timeout_stale_registrations staging2
    */5  * * * * rocky /var/www/register.rockthevote.com/rocky/current/script/cron_remove_buckets staging2
    

### e. Email

Email to registrants is sent by worker daemons running on the :util server.
Email to partners for e.g. password reset is sent from the :app server.

## 4. Deploy

### a. Setup (rvm/passenger)

The servers should be configured with all the required software libraries before
running this. They should also have their directory system set up according to
the configuration in the local .env file.)

Running the capistrano `deploy:setup` task will also invoke a number of custom
tasks (see `config/deploy.rb`) that will install RVM, ruby (the version
indicated in `.ruby-version`), set up a gemset (the gemset indicated in
`.ruby-gemset`), install passenger into that gemset, and run the
passenger-install-apache2-module script.

### b. Deploy (various symlinks)

Before running the first deploy, the deployment directory should have a shared/
directory set up with the following files:

* `shared/config/database.yml`
* `shared/config/newrelic.yml`
* `shared/.env.<env>`

When your code changes are pushed to git origin/master, run

    $ cap <environment_name> deploy

To deploy a specific tag or commit (highly recommended):

    $ cap <environment_name> deploy -Srev=<commit-hash|tag|branch>

### c. Utility Daemons

There are two worker daemons running on the utility server. They can be managed
locally with control scripts or remotely with capistrano.

    $ script/rocky_runner start
    $ script/rocky_runner stop
    $ script/rocky_pdf_runner start
    $ script/rocky_pdf_runner stop

    $ cap deploy:run_workers    # start/restart both workers
    
The `deploy:run_workers` task also runs during a full deploy

#### `rocky_runner`

The `rocky_runner` daemon pulls jobs out of the delayed job queue and runs them.
There are two kinds of jobs: completing a registration and sending a reminder
email. Completing the registration includes generating the PDF, which uses the
second daemon to do that work.

#### `rocky_pdf_runner`

It would be nice to have both daemons merged into one process, but it was faster
to set things up this way. In the future, using JRuby would let someone do
that. For now, we use the second daemon to avoid paying the cost of launching a
Java VM for every PDF merger.

## 5. Importing State Data

The application is set up to import updates to state-specific data. You'll want
to do this once before launching, then whenever changes are necessary. You can
do this by updating the states.yml file in your repository and by doing a full
deploy.

## 6. Server Monitoring

The application is configured with basic monitoring. NewRelic RPM for
performance, and Airbrake for exception monitoring. New developers can be added
to those accounts to get access and email updates.

# Development and testing

The cucumber feature that exercises the PDF Merge will run either in-process, or
with the daemon. If the daemon is running, it will use that. If the daemon is
not running, it will shell out to java to run the merge directly.

Run the rspec test suite:

    $ bundle exec rspec spec/

Run the features with cucumber:

    $ bundle exec cucumber

## Load Testing

### From the development workstation

There is a script at spec/api_load_test.rb that can run multi-threaded tests against the registration API.
In the file, edit the config section at the top to specify the number of threads and requests-per-thread
and other details like which server to test. 

Once you have the monitor running, run the load test script via

    $ bundle exec ruby spec/api_load_test.rb
    
    
### Loader.io
    
You can also do more extensive load tests with loader.io. You'll need to create an account and 
verify the host you're testing against. Then create a new scenario with the Client Requests section set to

    method: POST 
    protocol: https
    host: [the host you're testing]
    path: api/v3/registrations.json?registration%5Bdate_of_birth%5D=11-05-1955&registration%5Blang%5D=en&registration%5Bcollect_email_address%5D=no&registration%5Bfirst_name%5D=firststage%20&registration%5Bmiddle_name%5D=middlestage&registration%5Blast_name%5D=lastStage&registration%5Bhome_address%5D=101%20Address%201&registration%5Bhome_unit%5D=420&registration%5Bhome_city%5D=Waltham&registration%5Bhome_state_id%5D=MA&registration%5Bhome_zip_code%5D=02453&registration%5Bname_title%5D=Mr.&registration%5Bpartner_id%5D=7&registration%5Bparty%5D=Democratic&registration%5Brace%5D=Other&registration%5Bid_number%5D=Waltham&registration%5Bus_citizen%5D=1&registration%5Bopt_in_email%5D=1&registration%5Bopt_in_sms%5D=0&registration%5Bphone%5D=123-456-7890&registration%5Bphone_type%5D=Home

Depending on the host you're testing, you may also need to open Advanced Settings in the Test Settings section and set the 
username and password under Basic authentication.


## Clean Start

The application includes a set of bootstrap data that will let it get going.
WARNING: running the bootstrap process will reset the partners and state data in
the application. To bootstrap, run:

    $ bundle exec rake db:bootstrap

There is no rake task to reset the registrant data. If you want to do that,
drop into mysql and truncate the registrants table. You probably want to do
this before going live to clear out any bogus test data.

# Additional Notes

* The set of files for config is likely to change


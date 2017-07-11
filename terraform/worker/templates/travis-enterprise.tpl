# Options for the 'travis-enterprise' service
# This file belongs in /etc/default on the travis worker machine

export TRAVIS_ENTERPRISE_BUILD_ENDPOINT="__build__"
export TRAVIS_ENTERPRISE_HOST="${platform_fqdn}"
export TRAVIS_ENTERPRISE_SECURITY_TOKEN="${rabbitmq_password}"

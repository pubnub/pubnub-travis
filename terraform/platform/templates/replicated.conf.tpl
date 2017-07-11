{
    "DaemonAuthenticationType": "password",
    "DaemonAuthenticationPassword": "${platform_admin_password}",
    "TlsBootstrapType": "server-path",
    "TlsBootstrapHostname": "${platform_fqdn}",
    "TlsBootstrapCert": "/opt/pubnub/certs/${platform_fqdn}.crt",
    "TlsBootstrapKey": "/opt/pubnub/certs/${platform_fqdn}.key",
    "LogLevel": "${replicated_log_level}",
    "Channel": "stable",
    "LicenseFileLocation": "/opt/pubnub/travis-platform/travis-trial-license.rli",
    "ImportSettingsFrom": "/opt/pubnub/travis-platform/settings.json",
    "BypassPreflightChecks": "${bypass_preflight_checks}"
}

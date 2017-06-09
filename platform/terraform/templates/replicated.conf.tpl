{
    "DaemonAuthenticationType": "password",
    "DaemonAuthenticationPassword": "${admin_password}",
    "TlsBootstrapType": "server-path",
    "TlsBootstrapHostname": "${fqdn}",
    "TlsBootstrapCert": "/opt/pubnub/certs/${fqdn}.crt",
    "TlsBootstrapKey": "/opt/pubnub/certs/${fqdn}.key",
    "LogLevel": "${log_level}",
    "Channel": "stable",
    "LicenseFileLocation": "/opt/pubnub/travis-platform/travis-trial-license.rli",
    "ImportSettingsFrom": "/opt/pubnub/travis-platform/settings.json",
    "BypassPreflightChecks": true
}

using System.Net;
using System;

public static class ProxyClient
{
    public static HttpClient GetProxyHttpClient(string proxyAdress, ICredentials? credentials,
        string defaultRequestHeader)
    {
        ICredentials? _credentials = null;
        _credentials = credentials ?? null;

        var proxy = new WebProxy
        {
            Address = new Uri(proxyAdress),
            BypassProxyOnLocal = false,
            UseDefaultCredentials = false,
            Credentials = _credentials
        };
        var handler = new HttpClientHandler
        {
            Proxy = proxy,
            UseProxy = true,
            ServerCertificateCustomValidationCallback =
                (message, cert, chain, errors) => true // Disable SSL certificate validation for testing purposes
        };

        var client = new HttpClient(handler);

        client.DefaultRequestHeaders.UserAgent.ParseAdd(
            $"{defaultRequestHeader}/1.0 (compatible; {defaultRequestHeader}/1.0; +http://{defaultRequestHeader}.com)");

        return client;
    }

    public static HttpClient GetProxyHttpClient(string proxyAdress)
    {
        var proxy = new WebProxy
        {
            Address = new Uri(proxyAdress),
            BypassProxyOnLocal = false,
            UseDefaultCredentials = false,
        };
        var handler = new HttpClientHandler
        {
            Proxy = proxy,
            UseProxy = true,
            ServerCertificateCustomValidationCallback =
                (message, cert, chain, errors) => true // Disable SSL certificate validation for testing purposes
        };

        return new HttpClient(handler);
    }
}
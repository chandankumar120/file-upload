#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide for a comprehensive documentation
# at https://www.varnish-cache.org/docs/.

# Marker to tell the VCL compiler that this VCL has been written with the
# 4.0 or 4.1 syntax.

vcl 4.1;

import std;

backend default {
    .host = "127.0.0.1";
    .port = "8080";
    .first_byte_timeout = 300s;
    .between_bytes_timeout = 60s;
    .probe = {
        .url = "/";
        .interval = 5s;
        .timeout = 1s;
        .window = 5;
        .threshold = 3;
    }
}

acl purge {
    "localhost";
    "127.0.0.1";
    "::1";
}

sub vcl_recv {

    # Bypass Varnish for all paths EXCEPT /cs-cart-versions/varnish/
    if (req.url !~ "^/cs-cart-versions/varnish/") {
        return (pass);
    }

    # Initialize debug headers
    unset req.http.X-Debug;
    set req.http.X-Debug = "Recv-start";

    # Handle HTTPS
    if (req.http.X-Forwarded-Proto == "https") {
        set req.http.X-Forwarded-Port = "443";
    } else {
        set req.http.X-Forwarded-Port = "80";
    }
    set req.http.X-Debug = req.http.X-Debug + ",HTTPS-handled";

    # Normalize host header
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");
    set req.http.X-Debug = req.http.X-Debug + ",Host-normalized";

    # Handle PURGE requests
    if (req.method == "PURGE") {
        set req.http.X-Debug = req.http.X-Debug + ",PURGE-received";
        if (!client.ip ~ purge) {
            set req.http.X-Debug = req.http.X-Debug + ",PURGE-denied";
            return (synth(405, "Not allowed"));
        }
        set req.http.X-Debug = req.http.X-Debug + ",PURGE-allowed";
        return (purge);
    }

    # Bypass cache for POST requests
    if (req.method == "POST") {
        set req.http.X-Debug = req.http.X-Debug + ",POST-pass";
        set req.http.X-Pass-Reason = "POST request";
        return (pass);
    }

    # Bypass cache for admin and authenticated users
    if (req.url ~ "^/(admin(\.php)?|index\.php\?dispatch=(auth|profiles\.update|cart|checkout))") {
        set req.http.X-Debug = req.http.X-Debug + ",Admin-pass";
        set req.http.X-Pass-Reason = "Admin/checkout URL";
        return (pass);
    }

    # Cookie inspection
    if (req.http.Cookie) {
        set req.http.X-Debug = req.http.X-Debug + ",Cookie-found";
        set req.http.X-Original-Cookie = req.http.Cookie;
        
        # Remove tracking cookies but keep session cookies for detection
        set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js|utm_[a-z]+|gclid|fbclid)=", ";");
        set req.http.Cookie = regsuball(req.http.Cookie, ";+", ";");
        set req.http.Cookie = regsub(req.http.Cookie, "^;|;$", "");
        
        if (req.http.Cookie ~ "(sid_customer_|sid_admin_|PHPSESSID)") {
            set req.http.X-Debug = req.http.X-Debug + ",Session-cookie";
            set req.http.X-Pass-Reason = "Session cookie: " + regsub(req.http.Cookie, ".*?(sid_customer_[^=]+|sid_admin_[^=]+|PHPSESSID=[^;]+).*", "\1");
            return (pass);
        }
        
        if (req.http.Cookie == "") {
            unset req.http.Cookie;
            set req.http.X-Debug = req.http.X-Debug + ",Cookie-cleaned";
        } else {
            set req.http.X-Debug = req.http.X-Debug + ",Other-cookies";
        }
    } else {
        set req.http.X-Debug = req.http.X-Debug + ",No-cookies";
    }

    # Static files handling
    if (req.url ~ "^/[^?]+\.(css|js|jpg|jpeg|png|gif|ico|woff2?|svg|webp|mp4|mp3|eot|ttf)(\?.*)?$") {
        set req.http.X-Debug = req.http.X-Debug + ",Static-file";
        unset req.http.Cookie;
    }

    set req.http.X-Debug = req.http.X-Debug + ",Proceed-to-hash";
    return (hash);
}

sub vcl_hash {
    set req.http.X-Debug = req.http.X-Debug + ",Hash-start";
    
    # Standard hash on URL and host
    hash_data(req.url);
    hash_data(req.http.host);
    
    # Include device detection if needed
    if (req.http.User-Agent) {
        hash_data(req.http.User-Agent);
        set req.http.X-Debug = req.http.X-Debug + ",UA-hashed";
    }
    
    # Cache variations by protocol
    if (req.http.X-Forwarded-Proto) {
        hash_data(req.http.X-Forwarded-Proto);
        set req.http.X-Debug = req.http.X-Debug + ",Proto-hashed";
    }
    
    set req.http.X-Debug = req.http.X-Debug + ",Hash-complete";
    return (lookup);
}

sub vcl_hit {
    set req.http.X-Debug = req.http.X-Debug + ",Hit-start";
    
    if (obj.ttl >= 0s) {
        set req.http.X-Debug = req.http.X-Debug + ",Fresh-hit";
        return (deliver);
    }
    
    if (std.healthy(req.backend_hint)) {
        if (obj.ttl + 300s > 0s) {
            set req.http.X-Debug = req.http.X-Debug + ",Grace-hit";
            return (deliver);
        } else {
            set req.http.X-Debug = req.http.X-Debug + ",Stale-restart";
            return (restart);
        }
    } else {
        if (obj.ttl + obj.grace > 0s) {
            set req.http.X-Debug = req.http.X-Debug + ",Unhealthy-grace";
            return (deliver);
        } else {
            set req.http.X-Debug = req.http.X-Debug + ",Unhealthy-restart";
            return (restart);
        }
    }
}

sub vcl_miss {
    set req.http.X-Debug = req.http.X-Debug + ",Miss";
    return (fetch);
}

sub vcl_backend_response {

    # Only apply caching rules to /cs-cart-versions/varnish/
    if (bereq.url !~ "^/cs-cart-versions/varnish/") {
        set beresp.uncacheable = true;
        set beresp.ttl = 0s;
        return (deliver);
    }

    set beresp.http.X-Debug = "Backend-response-start";
    
    # Never cache errors
    if (beresp.status >= 400) {
        set beresp.http.X-Debug = beresp.http.X-Debug + ",Error-status";
        set beresp.uncacheable = true;
        set beresp.ttl = 0s;
        return (deliver);
    }

    # Don't cache responses with Set-Cookie
    if (beresp.http.Set-Cookie && !(bereq.url ~ "^/(static|uploads)/")) {
        set beresp.http.X-Debug = beresp.http.X-Debug + ",Set-Cookie";
        set beresp.uncacheable = true;
        set beresp.ttl = 0s;
        return (deliver);
    }

    # Force no-cache for admin/checkout
    if (bereq.url ~ "^/(admin|index\.php\?dispatch=(auth|profiles\.update|cart|checkout))" ||
        bereq.http.Cookie ~ "(sid_customer_|sid_admin_|PHPSESSID)") {
        set beresp.http.X-Debug = beresp.http.X-Debug + ",Admin-backend";
        set beresp.uncacheable = true;
        set beresp.ttl = 0s;
        return (deliver);
    }

    # Remove Set-Cookie for cacheable content
    unset beresp.http.Set-Cookie;
    set beresp.http.X-Debug = beresp.http.X-Debug + ",Cookie-removed";

    # Static files - long cache
    if (bereq.url ~ "^/[^?]+\.(css|js|jpg|jpeg|png|gif|ico|woff2?|svg|webp|mp4|mp3|eot|ttf)(\?.*)?$") {
        set beresp.ttl = 1y;
        set beresp.http.Cache-Control = "public, max-age=31536000, immutable";
        set beresp.http.X-Debug = beresp.http.X-Debug + ",Static-cached";
    }
    # Dynamic content - shorter cache
    else {
        set beresp.ttl = 15m;
        set beresp.http.Cache-Control = "public, max-age=900";
        set beresp.http.X-Debug = beresp.http.X-Debug + ",Dynamic-cached";
    }

    # Grace mode
    set beresp.grace = 2h;
    set beresp.keep = 24h;
    set beresp.http.X-Debug = beresp.http.X-Debug + ",Grace-set";
    
    return (deliver);
}

sub vcl_deliver {
    
    # Cache status
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT (" + obj.hits + ")";
    } else {
        set resp.http.X-Cache = "MISS";
        set resp.http.X-Cache-Reason = "First request or uncacheable";
    }

    # Debug why cache was bypassed
    if (req.http.X-Pass) {
        set resp.http.X-Cache-Reason = req.http.X-Pass;
    }
    
    # Backend cache control headers
    if (resp.http.Cache-Control) {
        set resp.http.X-Backend-Cache-Control = resp.http.Cache-Control;
    }
    
    # Request details
    set resp.http.X-Cache-URL = req.url;
    set resp.http.X-Cache-Host = req.http.host;
}


sub vcl_purge {
    return (synth(200, "Purged"));
}

sub vcl_synth {
    if (resp.status == 405) {
        set resp.http.Content-Type = "text/html; charset=utf-8";
        set resp.http.Retry-After = "5";
        synthetic( {"<!DOCTYPE html>
<html>
<head>
    <title>405 Not Allowed</title>
</head>
<body>
    <h1>Error 405 Not Allowed</h1>
    <p>Purge request not allowed from this IP.</p>
</body>
</html>"} );
        return (deliver);
    }
    
    if (resp.status == 503) {
        set resp.http.Content-Type = "text/html; charset=utf-8";
        set resp.http.Retry-After = "5";
        synthetic( {"<!DOCTYPE html>
<html>
<head>
    <title>503 Service Unavailable</title>
</head>
<body>
    <h1>Error 503 Service Unavailable</h1>
    <p>Varnish cache server is temporarily unavailable.</p>
</body>
</html>"} );
        return (deliver);
    }
}

sub vcl_hit {
    if (obj.ttl >= 0s) {
        return (deliver);
    }
    
    if (std.healthy(req.backend_hint)) {
        if (obj.ttl + 300s > 0s) {
            return (deliver);
        } else {
            return (restart);
        }
    } else {
        if (obj.ttl + obj.grace > 0s) {
            return (deliver);
        } else {
            return (restart);
        }
    }
}

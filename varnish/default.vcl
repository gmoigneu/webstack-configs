backend default {
  .host = "127.0.0.1";
  .port = "81";
  .connect_timeout = 3600s;
  .first_byte_timeout = 3600s;
  .between_bytes_timeout = 3600s;
}

acl admins {
  "localhost";
}

sub vcl_recv {
  #
  # general: ne depend ni du backend ni de la requete
  #

  # get real IP
  set req.http.X-Custom-IP = client.ip;
  if (req.http.X-Real-IP) {
    set req.http.X-Custom-IP = req.http.X-Real-IP;
  }  
  remove req.http.X-Real-Forwarded-For;
  remove req.http.X-Forwarded-For;
  set req.http.X-Real-Forwarded-For = req.http.X-Custom-IP;
  set req.http.X-Forwarded-For = req.http.X-Custom-IP;
  set req.http.X-Real-IP = req.http.X-Custom-IP;

  # traitement des PURGE
  if (req.request == "PURGE"){
    if (!client.ip ~ admins){
      error 400 "Bad request";
    }
    return(lookup);
  }

  # requete pas conforme HTTP
  if (!req.request ~ "GET|HEAD|PUT|POST|TRACE|OPTIONS|DELETE") {
    error 400 "Bad request";
  }

	if (req.url ~ "^/(phpmyadmin|_phpmyadmin)") {
    return (pass);
  }

  #
  # non generique
  # 
  # si le backend ne repond pas on a le droit de servir du cache expiré depuis 2 minutes
	# POUR PASSAGE TV
  set req.grace = 3600s;

	set req.backend = default;

  # le bon backend doit etre defini sinon les POST vont arrivés sur le backend par defaut
  # on ne traite en terme de cache que les GET et les HEAD
  if (req.request != "GET" && req.request != "HEAD") {
          return (pass);
  }

  #
  # Vhosts
  #
  if ( req.http.host ~ "^(www\.)?example.(com|fr|co\.uk)" ) {
    if (req.url == "/varnish/index/purgeall/key/#fjeIJbfgOKJZA") {
            ban_url(".*");
    }

		if (req.url ~ "^/purge/") {
      if (!client.ip ~ admins){
        error 400 "Bad request";
      }

      set req.url = regsub(req.url, "^/purge/(.*)", "/\1"); 
      ban("req.url ~ "+req.url+" && req.http.host == "+req.http.host);
      error 200 "Purged."; 
    }

    # we should not cache any page for Magento backend
    if (req.url ~ "^/(admin|index.php/admin)") {
      return (pass);
    }
		
    if (req.url ~ "^/exports/") {
      return (pipe);
    }

    if (req.url ~ "\.(txt|js|css|eot|woff|ttf|htc|jpe?g|gif|png|ico)(\?.*)?$") {
      unset req.http.Cookie;
    }

    # we should not cache any page for checkout and customer modules
    if (req.url ~ "^/(index\.php/)?(checkout|customer|manager|moneybookers|paypal|wishlist|cybermut)") {
      return (pass);
    }
		
    # do not cache till session end
    if (req.http.cookie ~ "(nocache_stable|adminhtml)") {
      return (pass);
    }

    #unique identifier witch tell Varnish use cache or not
    if (req.http.cookie ~ "nocache") {
      return (pass);
    }
    return(lookup);
  }
  else {
          return(pass);
  }
        	
  # par defaut on ne cache pas et on forwarde sur le backend web (ie le cluster de frontaux webs)
  return (pass);
}

sub vcl_fetch {
  if (beresp.http.content-type ~ "text" || beresp.http.content-type ~ "application/(javascript|json|xml|xhtml+xml|x-font-ttf|x-font-opentype|vnd.ms-fontobject)" || beresp.http.content-type ~ "image/(svg+xml|x-icon)") {
    set beresp.do_gzip = true;
  }

  if (beresp.status >= 500 && beresp.status <= 505) {
    error beresp.status;
  }

  if (beresp.status == 403) {
    error beresp.status;
  }

  if (req.request != "GET" && req.request != "HEAD") {
    return (hit_for_pass);
  }

	if (req.url ~ "^/(phpmyadmin|_phpmyadmin)") {
    return (hit_for_pass);
  }

  #
  # Vhosts
  #
  if ( req.http.host ~ "^(www\.)?example.(com|fr|co\.uk)" ) {
    # we should not cache any page for Magento backend
    if (req.url ~ "^/(admin|index.php/admin)") {
      return (hit_for_pass);
    }

    if (req.url ~ "\.(txt|js|css|eot|woff|ttf|htc|jpe?g|gif|png|ico)(\?.*)?$") {
      unset req.http.Cookie;
    }

    # we should not cache any page for checkout and customer modules
    if (req.url ~ "^/(index\.php/)?(checkout|customer|manager|moneybookers|paypal|wishlist)") {
      return (hit_for_pass);
    }

    # do not cache till session end
    if (req.http.cookie ~ "(nocache_stable|adminhtml)") {
      return (hit_for_pass);
    }

    #unique identifier witch tell Varnish use cache or not
    if (req.http.cookie ~ "nocache") {
      return (hit_for_pass);
    }
    if( beresp.http.Cache-Control ~ "private") {
      set beresp.http.X-Cacheable = "NO:Cache-Control=private";
      return (hit_for_pass);
    }

    # cache
    unset beresp.http.expires;
    unset beresp.http.Cache-Control;
    unset beresp.http.Etag;
    unset beresp.http.Set-Cookie;
    unset beresp.http.Vary;
    set beresp.http.Cache-Control = "private, no-cache, no-store";
    if ( beresp.ttl < 1s ) {
      set beresp.ttl   = 24h;
      set beresp.grace = 24h;
      set beresp.http.X-Cacheable = "YES:FORCED";
    }
    else {
      set beresp.ttl   = 24h;
      set beresp.grace = 24h;
      set beresp.http.X-Cacheable = "YES";
    }

    return (deliver);
  }

  #
  # pas de cache
  #
	return (hit_for_pass);
}

sub vcl_pass {
  return (pass);
}

sub vcl_hit {
  if (req.request == "PURGE") {
    purge;
    error 200 "Purged.";
  }
  if (req.http.Cache-Control ~ "no-cache") {
    purge;
  }

  return (deliver);
}

sub vcl_miss {
  if (req.request == "PURGE") {
    error 404 "Not in cache.";
  }
  
  return (fetch);
}

sub vcl_hash {
  hash_data(req.url);

  if (req.http.host) {
    hash_data(req.http.host);
  }
  else {
    hash_data(server.ip);
  }
  return (hash);
}

sub vcl_deliver {
  if (obj.hits > 0) {
    set resp.http.X-Cache = "HIT";
  } 
  else {
    set resp.http.X-Cache = "MISS";
  }
  remove resp.http.X-Varnish-IP;
  set    resp.http.X-Varnish-IP = server.ip;
  
  return (deliver);
}

sub vcl_error {
  if (obj.status == 401) {
    set obj.http.Content-Type = "text/html; charset=utf-8";
    set obj.http.WWW-Authenticate = "Basic realm=Secured";
    synthetic {"401 Unauthorized"};
    return (deliver);
  }
  if ((obj.status >= 500 && obj.status <= 505) && req.http.host ~ "^(www\.)?example.(com|fr|co\.uk)") {
    set obj.http.Content-Type = "text/html; charset=utf-8";
    synthetic {"Error 500"};
    return (deliver);
  }
}


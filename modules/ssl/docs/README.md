# SSL Module

Platform SSL policy is centralized here.

Other modules should call:

```bash
platform_ssl_issue "$domain"
platform_ssl_verify "$domain"
platform_ssl_remove "$domain"
```

rather than invoking Certbot directly.

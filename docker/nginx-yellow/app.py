def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": '<html><body style="background-color:#f9a825;color:white;text-align:center;padding:50px;font-family:Arial,sans-serif;"><h1>NGINX Service</h1><h2 style="background:rgba(255,255,255,0.2);display:inline-block;padding:10px 30px;border-radius:50px;">YELLOW - v3.0 (Latest)</h2><p>Brand New Release with Major Features</p><p>Host: nginx.jayakrishnayadav.cloud</p><hr style="border-color:rgba(255,255,255,0.3);"><p><small>Custom Blue-Green Deployment | No CodeDeploy</small></p></body></html>',
        "isBase64Encoded": False
    }

# ServiceNow PDI setup for this lab
#
# 1. Create free PDI: https://developer.servicenow.com
#    Sign in → Request Instance → pick latest release → wait until ready
# 2. Open instance (Start Building). Default admin user is usually "admin".
# 3. Copy instance URL, e.g. https://dev12345.service-now.com
# 4. Create local .env (never commit):
#
#    SNOW_INSTANCE=https://devXXXXX.service-now.com
#    SNOW_USER=admin
#    SNOW_PASSWORD=your-pdi-password
#
# 5. Tell Cursor: "snow credentials ready"
#    We store them in AWS Secrets Manager and deploy Lambda → SNS.
#
# PDI tip: after ~90 days, log into the PDI directly at least every 10 days
# so ServiceNow does not reclaim it.

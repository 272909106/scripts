build_name=saas-ops-cn-north-1.jcr.service.jdcloud.com/pro/tomcat:7088
docker build -t $build_name .
docker push $build_name

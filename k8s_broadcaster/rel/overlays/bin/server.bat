if "%DISTRIBUTION_MODE%"=="k8s" (
  set RELEASE_DISTRIBUTION=name
  set RELEASE_NODE="k8s_broadcaster@%POD_IP%"
)

set PHX_SERVER=true
call "%~dp0\k8s_broadcaster" start

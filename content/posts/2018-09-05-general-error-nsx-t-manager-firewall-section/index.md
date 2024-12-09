---
title: "\"General Error\" NSX-T Manager Firewall Section"
date: "2018-09-05"
#thumbnail: "/images/VMW-NSX-Logo1.jpg"
categories: 
  - Networking
  - Security
tags:
  - distributed-firewall 
  - nsx
  - troubleshooting

---

If you have missing objects in the firewall section before upgrading from NSX-T 2.1 to 2.2 you will experience a General Error in the GUI, on the Dashboard, and in the Firewall section of the GUI. You will even get general error when doing API calls to list the DFW sections https://NSXMGRIP/api/v1/firewall/sections: `{ "module\_name" : "common-services", "error\_message" : "General error has occurred.", "details" : "java.lang.NullPointerException", "error\_code" : "100" }`

If you have upgraded the fix is straight forward. Go to the following [KB](https://kb.vmware.com/s/article/56611) and dowload the attached jar file.

Upload this jar file to the NSX-T manager by logging in with root and do a scp command from where you downloaded it. ex: `"scp your\_username@remotehost:nsx-firewall-1.0.jar /tmp"`

Then replace the existing file with the one from the kb article placed here: `/opt/vmware/proton-tomcat/webapps/nsxapi/WEB-INF/lib#`

Reboot

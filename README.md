# GoogleReporter
<h>Google Report Custom</h>

---------------------------------------------
++Note: 
**This dependcies : 
  - RxSwift
  - RxCocoa

Using custom report from Google Analytic but only using some features :
+ Send event
+ Send window screens
+ Send fatal error

*How to use:
You must set your tracker ID UA-XXXXX-XX with GoogleReporter.shared.configure()

Send report:
  - GoogleReporter.shared.screenView(nName)

Send event:
  - GoogleReporter.shared.screenView(nName)

Send fatal:
  - GoogleReporter.shared.exception("error",true)

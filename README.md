# GoogleReporter
<h>Google Report Custom</h>
---------------------------------------------
<h2>++Note: </h2>

++++++++++++++++++++

<b><i>**This dependcies : </i></b>
  - RxSwift
  - RxCocoa

<blockquote> Using custom report from Google Analytic but only using some features :</blockquote>

---------------------------------------------

+ Send event
+ Send window screens
+ Send fatal error
+ Send Timing

---------------------------------------------

<h3>*How to use:</h3>
<i>You must set your tracker ID UA-XXXXX-XX with GoogleReporter.shared.configure()</i>

<h3>Function:</h3>
<table style="width:100%">
  <tr>
    <th>Send Type</th>
    <th>Syntax</th> 
  </tr>
  <tr>
    <td>ScreenView</td>
    <td>GoogleReporter.shared.screenView(nName)</td>
  </tr>
  <tr>
    <td>Event</td>
    <td>GoogleReporter.shared.event("category","action")</td>
  </tr>
  <tr>
    <td>Timing</td>
    <td>GoogleReporter.shared.timing("category","action"</td>
  </tr>
  <tr>
    <td>Fatal</td>
    <td>GoogleReporter.shared.exception("error",true)</td>
  </tr>
</table>
 
<h3>**To Use Objective -C :</h3>

- Please #import <GoogleReporter/GoogleReporter-Swift.h>


Ryfi - The Ruby Eye-Fi Framework
================================
Ryfi is written in Ruby and based on the lightweight Sinatra web framework. It provides OTA (Over The Air) receipt and manipulation of photos from one or many Eye-Fi cards. The Eye-Fi card is an SD-form-factor camera card with a built-in WiFi (802.11a/b/n) chipset. 

What can be done?
-----------------
The Eye-Fi card is a pretty nifty little device -- the moment you take a photo, it will attempt to connect to a pre-configured wireless network and upload the photo to your computer. Unfortunately, Eye-Fi has been less than forthcoming with any APIs, and there is no ability to extend their software other than with cumbersome folder watching techniques.

Out of the box, Ryfi doesn't do much; however, with a few lines of Ruby, you can get it to perform complex image transformations, post your pictures to Twitter, display them full-screen, etc. *almost instantly* from your camera.

Up and Running
--------------
To get Ryfi up and running, you'll need to install the following Ruby gems:

* Sinatra
* SOAP4r
* Builder

Install the Eye-Fi manager software, and configure your card to connect to the networks of your choosing. You'll need to procure the MAC address and upload key for each card -- on a Mac, simply take a look at the following XML file:

    ~/Library/Eye-Fi/Settings.xml

You'll need to write some sort of handler to provide an EyefiCard object for a given MAC. Take a look at the code in app.rb for a *rediculously* simple sample to get you started. Once you have your handler code in app.rb, just execute that file on the command line with Ruby:

    ruby ryfi/app.rb

Note that the MyApp class in app.rb extends the Sinatra base class. You can treat it as a Sinatra application and add get/post method handlers, etc. 

Well, I'm tired, so I'll write some more documentation later. Happy hunting!
/*
 * DesktopUtilsMac.mm
 *
 * Copyright (C) 2009-18 by RStudio, Inc.
 *
 * Unless you have received this program directly from RStudio pursuant
 * to the terms of a commercial license agreement with RStudio, then
 * this program is licensed to you under the terms of version 3 of the
 * GNU Affero General Public License. This program is distributed WITHOUT
 * ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF NON-INFRINGEMENT,
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. Please refer to the
 * AGPL (http://www.gnu.org/licenses/agpl-3.0.txt) for more details.
 *
 */

#include "DesktopUtils.hpp"

#include <boost/algorithm/string/predicate.hpp>

#include <core/system/Environment.hpp>

#import <Foundation/NSString.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#include "DockMenu.hpp"

using namespace rstudio;

namespace rstudio {
namespace desktop {

QString getFixedWidthFontList()
{
   NSArray* fonts = [[NSFontManager sharedFontManager]
                         availableFontNamesWithTraits: NSFixedPitchFontMask];
   return QString::fromNSString([fonts componentsJoinedByString: @"\n"]);
}

namespace {

NSWindow* nsWindowForMainWindow(QMainWindow* pMainWindow)
{
   NSView *nsview = (NSView *) pMainWindow->winId();
   return [nsview window];
}

static DockMenu* s_pDockMenu;

void initializeSystemPrefs()
{
   NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
   [defaults setBool:NO forKey: @"NSFunctionBarAPIEnabled"];

   // Remove (disable) the "Start Dictation..." and "Emoji & Symbols" menu items from the "Edit" menu
   [defaults setBool:YES forKey:@"NSDisabledDictationMenuItem"];
   [defaults setBool:YES forKey:@"NSDisabledCharacterPaletteMenuItem"];

   // Remove the "Enter Full Screen" menu item from the "View" menu
   [defaults setBool:NO forKey:@"NSFullScreenMenuItemEverywhere"];
}

} // anonymous namespace

double devicePixelRatio(QMainWindow* pMainWindow)
{
   NSWindow* pWindow = nsWindowForMainWindow(pMainWindow);

   if ([pWindow respondsToSelector:@selector(backingScaleFactor)])
   {
      return [pWindow backingScaleFactor];
   }
   else
   {
      return 1.0;
   }
}

bool isOSXMavericks()
{
   NSDictionary *systemVersionDictionary =
       [NSDictionary dictionaryWithContentsOfFile:
           @"/System/Library/CoreServices/SystemVersion.plist"];

   NSString *systemVersion =
       [systemVersionDictionary objectForKey:@"ProductVersion"];

   std::string version(
         [systemVersion cStringUsingEncoding:NSASCIIStringEncoding]);

   return boost::algorithm::starts_with(version, "10.9");
}

bool isCentOS()
{
   return false;
}

namespace {

bool supportsFullscreenMode(NSWindow* pWindow)
{
   return [pWindow respondsToSelector:@selector(toggleFullScreen:)];
}

} // anonymous namespace


bool supportsFullscreenMode(QMainWindow* pMainWindow)
{
   NSWindow* pWindow = nsWindowForMainWindow(pMainWindow);
   return supportsFullscreenMode(pWindow);
}

// see: https://bugreports.qt-project.org/browse/QTBUG-21607
// see: https://developer.apple.com/library/mac/#documentation/General/Conceptual/MOSXAppProgrammingGuide/FullScreenApp/FullScreenApp.html
void enableFullscreenMode(QMainWindow* pMainWindow, bool primary)
{
   NSWindow* pWindow = nsWindowForMainWindow(pMainWindow);

   if (supportsFullscreenMode(pWindow))
   {
      NSWindowCollectionBehavior behavior = [pWindow collectionBehavior];
      behavior = behavior | (primary ?
                             NSWindowCollectionBehaviorFullScreenPrimary :
                             NSWindowCollectionBehaviorFullScreenAuxiliary);
      [pWindow setCollectionBehavior:behavior];
   }
}

void toggleFullscreenMode(QMainWindow* pMainWindow)
{
   NSWindow* pWindow = nsWindowForMainWindow(pMainWindow);
   if (supportsFullscreenMode(pWindow))
      [pWindow toggleFullScreen:nil];
}

void initializeLang()
{
   // Not sure what the memory management rules are here, i.e. whether an
   // autorelease pool is active. Just let it leak, since we're only calling
   // this once (at the time of this writing).

   // We try to simulate the behavior of R.app.

   NSString* lang = nil;

   // Highest precedence: force.LANG. If it has a value, use it.
   NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
   [defaults addSuiteNamed:@"org.R-project.R"];
   lang = [defaults stringForKey:@"force.LANG"];
   if (lang && ![lang length])
   {
      // If force.LANG is present but empty, don't touch LANG at all.
      return;
   }

   // Next highest precedence: ignore.system.locale. If it has a value,
   // hardcode to en_US.UTF-8.
   if (!lang && [defaults boolForKey:@"ignore.system.locale"])
   {
      lang = @"en_US.UTF-8";
   }

   // Next highest precedence: LANG environment variable.
   if (!lang)
   {
      std::string envLang = core::system::getenv("LANG");
      if (!envLang.empty())
      {
         lang = [NSString stringWithCString:envLang.c_str()
                          encoding:NSASCIIStringEncoding];
      }
   }

   // Next highest precedence: Try to figure out language from the current
   // locale.
   if (!lang)
   {
      NSString* lcid = [[NSLocale currentLocale] localeIdentifier];
      if (lcid)
      {
         // Eliminate trailing @ components (OS X uses the @ suffix to append
         // locale overrides like alternate currency formats)
         std::string localeId = std::string([lcid UTF8String]);
         std::size_t atLoc = localeId.find('@');
         if (atLoc != std::string::npos)
         {
            localeId = localeId.substr(0, atLoc);
            lcid = [NSString stringWithUTF8String: localeId.c_str()];
         }

         lang = [lcid stringByAppendingString:@".UTF-8"];
      }
   }

   // None of the above worked. Just hard code it.
   if (!lang)
   {
      lang = @"en_US.UTF-8";
   }

   const char* clang = [lang cStringUsingEncoding:NSASCIIStringEncoding];
   core::system::setenv("LANG", clang);
   core::system::setenv("LC_CTYPE", clang);

   initializeSystemPrefs();
}

void finalPlatformInitialize(MainWindow* pMainWindow)
{
   // https://bugreports.qt.io/browse/QTBUG-61707
   [NSWindow setAllowsAutomaticWindowTabbing: NO];
   
   if (!s_pDockMenu)
   {
      s_pDockMenu = new DockMenu(pMainWindow);
   }
}

} // namespace desktop
} // namespace rstudio

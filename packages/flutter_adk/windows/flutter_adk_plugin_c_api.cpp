#include "include/flutter_adk/flutter_adk_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_adk_plugin.h"

void FlutterAdkPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_adk::FlutterAdkPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

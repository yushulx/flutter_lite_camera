#include "flutter_lite_camera_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <codecvt>

namespace flutter_lite_camera
{

  // static
  void FlutterLiteCameraPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "flutter_lite_camera",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<FlutterLiteCameraPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  FlutterLiteCameraPlugin::FlutterLiteCameraPlugin()
  {
    camera = new Camera();
  }

  FlutterLiteCameraPlugin::~FlutterLiteCameraPlugin()
  {
    delete camera;
  }

  void FlutterLiteCameraPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name().compare("getPlatformVersion") == 0)
    {
      std::ostringstream version_stream;
      version_stream << "Windows ";
      if (IsWindows10OrGreater())
      {
        version_stream << "10+";
      }
      else if (IsWindows8OrGreater())
      {
        version_stream << "8";
      }
      else if (IsWindows7OrGreater())
      {
        version_stream << "7";
      }
      result->Success(flutter::EncodableValue(version_stream.str()));
    }
    else if (method_call.method_name().compare("getDeviceList") == 0)
    {
      std::vector<CaptureDeviceInfo> devices = ListCaptureDevices();
      flutter::EncodableList deviceList;
      for (size_t i = 0; i < devices.size(); i++)
      {
        CaptureDeviceInfo &device = devices[i];

        std::wstring wstr(device.friendlyName);
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), NULL, 0, NULL, NULL);
        std::string utf8Str(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), &utf8Str[0], size_needed, NULL, NULL);

        deviceList.push_back(flutter::EncodableValue(utf8Str));
      }

      result->Success(flutter::EncodableValue(deviceList));
    }
    else if (method_call.method_name().compare("saveJpeg") == 0)
    {
      const auto *args = std::get_if<flutter::EncodableList>(method_call.arguments());
      if (args && args->size() == 4)
      {
        std::string filename = std::get<std::string>((*args)[0]);
        int width = std::get<int>((*args)[1]);
        int height = std::get<int>((*args)[2]);
        auto rgbdata = std::get<std::vector<uint8_t>>((*args)[3]);

        const unsigned char *rgbDataPtr = reinterpret_cast<const unsigned char *>(rgbdata.data());
        saveFrameAsJPEG(rgbDataPtr, width, height, filename);
        result->Success();
      }
      else
      {
        result->Error("INVALID_ARGUMENTS", "Invalid arguments for saveJpeg");
      }
    }
    else if (method_call.method_name().compare("open") == 0)
    {
      const auto *arguments = std::get_if<flutter::EncodableList>(method_call.arguments());

      if (arguments && !arguments->empty())
      {
        int index = std::get<int>((*arguments)[0]);
        bool success = camera->Open(index);
        result->Success(flutter::EncodableValue(success));
      }
      else
      {
        result->Error("InvalidArguments", "Expected camera index");
      }
    }
    else if (method_call.method_name().compare("listMediaTypes") == 0)
    {
      auto mediaTypes = camera->ListSupportedMediaTypes();
      flutter::EncodableList mediaTypeList;

      for (const auto &mediaType : mediaTypes)
      {
        flutter::EncodableMap mediaTypeMap;
        mediaTypeMap[flutter::EncodableValue("width")] = flutter::EncodableValue((int)mediaType.width);
        mediaTypeMap[flutter::EncodableValue("height")] = flutter::EncodableValue((int)mediaType.height);
        std::wstring wstr(mediaType.subtypeName);
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), NULL, 0, NULL, NULL);
        std::string utf8Str(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), &utf8Str[0], size_needed, NULL, NULL);
        mediaTypeMap[flutter::EncodableValue("format")] = flutter::EncodableValue(utf8Str);
        mediaTypeList.push_back(flutter::EncodableValue(mediaTypeMap));
      }

      result->Success(flutter::EncodableValue(mediaTypeList));
    }
    else if (method_call.method_name().compare("setResolution") == 0)
    {
      const auto *arguments = std::get_if<flutter::EncodableList>(method_call.arguments());
      if (arguments && arguments->size() == 2)
      {
        int width = std::get<int>((*arguments)[0]);
        int height = std::get<int>((*arguments)[1]);
        bool success = camera->SetResolution(width, height);
        result->Success(flutter::EncodableValue(success));
      }
      else
      {
        result->Error("InvalidArguments", "Expected width and height");
      }
    }
    else if (method_call.method_name().compare("captureFrame") == 0)
    {
      FrameData frame = camera->CaptureFrame();
      if (frame.rgbData)
      {
        flutter::EncodableMap frameMap;
        frameMap[flutter::EncodableValue("width")] = flutter::EncodableValue(frame.width);
        frameMap[flutter::EncodableValue("height")] = flutter::EncodableValue(frame.height);
        frameMap[flutter::EncodableValue("data")] = flutter::EncodableValue(std::vector<uint8_t>(frame.rgbData, frame.rgbData + frame.size));
        ReleaseFrame(frame);
        result->Success(flutter::EncodableValue(frameMap));
      }
      else
      {
        result->Error("CaptureFailed", "Failed to capture frame");
      }
    }
    else if (method_call.method_name().compare("release") == 0)
    {
      camera->Release();
      result->Success();
    }
    else if (method_call.method_name().compare("getWidth") == 0)
    {
      int width = camera->frameWidth;
      result->Success(flutter::EncodableValue(width));
    }
    else if (method_call.method_name().compare("getHeight") == 0)
    {
      int height = camera->frameHeight;
      result->Success(flutter::EncodableValue(height));
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace flutter_lite_camera

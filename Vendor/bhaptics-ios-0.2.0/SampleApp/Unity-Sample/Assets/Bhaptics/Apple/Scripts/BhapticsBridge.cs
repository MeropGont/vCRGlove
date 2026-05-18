using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;


public enum PlayPosition
{
    Vest,
    Head,
    ForearmL,
    ForearmR,
    HandL,
    HandR,
    FootL,
    FootR,
    GloveL,
    GloveR
}


[System.Serializable]
public class BDevice {
    public string name;
    public string id;
    public string position;
    public bool connected;
    public bool paired;
}

[System.Serializable]
internal class DeviceListData {
    public BDevice[] devices;
}

public class BhapticsBridge
{
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
    private const string libName = "__Internal";

    [DllImport(libName)]
    private static extern void BhapticsPlugin_scan();


    [DllImport(libName)]
    private static extern void BhapticsPlugin_stopScan();


    [DllImport(libName)]
    private static extern int BhapticsPlugin_isScanning();


    [DllImport(libName)]
    private static extern void BhapticsPlugin_pair(string deviceId);


    [DllImport(libName)]
    private static extern void BhapticsPlugin_unpair(string deviceId);


    [DllImport(libName)]
    private static extern string BhapticsPlugin_getDevices();

    [DllImport(libName)]
    private static extern void BhapticsPlugin_playMotors(string position, int length, byte[] bytes);

    [DllImport(libName)]
    private static extern void BhapticsPlugin_stop();

#endif


    public static void Scan() {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        BhapticsPlugin_scan();
#endif
    }

    public static void StopScan()
    {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        BhapticsPlugin_stopScan();
#endif
    }

    public static bool IsScanning()
    {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        return BhapticsPlugin_isScanning() > 0;
#endif

        return false;
    }


    public static void PlayMotors(PlayPosition position, byte[] bytes) {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        BhapticsPlugin_playMotors(position.ToString(), bytes.Length, bytes);
#endif
    }



    public static void Stop()
    {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        BhapticsPlugin_stop();
#endif
    }


    public static void Pair(string id) {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        Debug.LogFormat("Pair {0}", id);
        BhapticsPlugin_pair(id);
#endif
    }


    public static void Unpair(string id)
    {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        Debug.LogFormat("Unpair {0}", id);
        BhapticsPlugin_unpair(id);
#endif
    }



    public static BDevice[] GetDevices()
    {
#if (UNITY_STANDALONE_OSX || UNITY_IOS) && !UNITY_EDITOR
        try
        {

            var devicesStr = BhapticsPlugin_getDevices();
            var deviceData = JsonUtility.FromJson<DeviceListData>("{\"devices\":" + devicesStr + "}");


            if (deviceData == null) {
                return new BDevice[] { };
            }

            return deviceData.devices;
        }
        catch (Exception e) {
            Debug.LogErrorFormat("GetDevices Exception {0}", e.Message);

        }
#endif
        return new BDevice[] { };
    }

}

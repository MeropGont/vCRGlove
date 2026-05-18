using System.IO;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;

public class BhapticsPostBuild
{
    [PostProcessBuild]
    public static void SetXcodePlist(BuildTarget buildTarget, string pathToBuiltProject)
    {
        if (buildTarget != BuildTarget.iOS) return;

        var plistPath = pathToBuiltProject + "/Info.plist";
        var plist = new PlistDocument();
        plist.ReadFromString(File.ReadAllText(plistPath));

        var rootDict = plist.root;
        rootDict.SetString("NSBluetoothAlwaysUsageDescription", "Please agree to use bHaptics devices");
        rootDict.SetString("NSBluetoothPeripheralUsageDescription", "Please agree to use bHaptics devices");

        File.WriteAllText(plistPath, plist.WriteToString());
    }
}

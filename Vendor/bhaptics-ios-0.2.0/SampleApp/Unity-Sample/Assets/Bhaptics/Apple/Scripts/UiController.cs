using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

public class UiController : MonoBehaviour
{

    public PlayPosition position = PlayPosition.Vest;
    private byte[] bytes = new byte[40];


    [SerializeField]
    private Button ScanButton;


    [SerializeField]
    private Button PlayButton;


    [SerializeField]
    private Button StopButton;

    [SerializeField]
    private RectTransform container;

    [SerializeField]
    private DeviceUIController uiPrefab;


    private List<DeviceUIController> deviceUiComponents = new List<DeviceUIController>();
    void Start()
    {
        for (int i = 0; i < 20; i++)
        {
            var ui = Instantiate(uiPrefab, container.transform);
            deviceUiComponents.Add(ui);

            ui.gameObject.SetActive(false);
        }


        if (ScanButton != null) {
            ScanButton.onClick.AddListener(OnScanClick);
        }


        if (PlayButton != null)
        {
            PlayButton.onClick.AddListener(OnPlay);
        }


        if (StopButton != null)
        {
            StopButton.onClick.AddListener(OnStop);
        }


        InvokeRepeating("Refresh", 0f, 1f);
    }


    private void OnScanClick() {
        if (BhapticsBridge.IsScanning())
        {
            BhapticsBridge.StopScan();
        } else
        {
            BhapticsBridge.Scan();
        }


        CheckScanning();  
    }

    private void CheckScanning()
    {
        ScanButton.gameObject.GetComponentInChildren<TMPro.TextMeshProUGUI>().text = BhapticsBridge.IsScanning() ? "Scanning" : "Scan";

    }

    private void OnStop()
    {
        StopAllCoroutines();
        BhapticsBridge.Stop();
    }

    private void OnPlay()
    {
        StopAllCoroutines();
        StartCoroutine(Play());
    }

    private IEnumerator Play()
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            ClearBytes();
            bytes[index] = 100;
            BhapticsBridge.PlayMotors(position, bytes);
            yield return new WaitForSeconds(.3f);
        }

        OnStop();
        yield return new WaitForSeconds(.1f);
    }

    private void ClearBytes()
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            bytes[index] = 0;
        }
    }

    private void Refresh()
    {
        var devices = BhapticsBridge.GetDevices();


        for (int i = 0; i < deviceUiComponents.Count; i++)
        {
            if (i < devices.Length)
            {
                deviceUiComponents[i].RefreshDevice(devices[i]);
                deviceUiComponents[i].gameObject.SetActive(true);
            }
            else
            {
                deviceUiComponents[i].RefreshDevice(null);
                deviceUiComponents[i].gameObject.SetActive(false);
            }
            
        }

        CheckScanning();
    }
}

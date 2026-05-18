using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

public class DeviceUIController : MonoBehaviour
{

    [SerializeField]
    private Button pairButton;

    [SerializeField]
    private TMPro.TextMeshProUGUI deviceNameText;


    [SerializeField]
    private TMPro.TextMeshProUGUI status;


    [SerializeField]
    private TMPro.TextMeshProUGUI position;


    private BDevice device;

    public void RefreshDevice(BDevice device) {

        this.device = device;
        if (device == null) {
            return;
        }

        var text = pairButton.gameObject.GetComponentInChildren<TMPro.TextMeshProUGUI>();
        if (device.paired)
        {
            text.text = "Unpair";
        }
        else {
            text.text = "Pair";
        }

        deviceNameText.text = device.name;
        status.text = device.connected ? "O" : "X";
        position.text = device.position;
    }

    void Start()
    {
        if (pairButton != null) {
            pairButton.onClick.AddListener(OnClick);
        }
    }

    private void OnClick() {
        if (device == null) {
            return;
        }

        if (device.paired)
        {
            BhapticsBridge.Unpair(device.id);
        } else
        {
            BhapticsBridge.Pair(device.id);

        }

        
    }

}

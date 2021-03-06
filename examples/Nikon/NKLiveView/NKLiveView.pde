#include <inttypes.h>
#include <avr/pgmspace.h>

#include <avrpins.h>
#include <max3421e.h>
#include <usbhost.h>
#include <usb_ch9.h>
#include <Usb.h>
#include <usbhub.h>
#include <address.h>

#include <message.h>
#include <parsetools.h>
#include <eoseventdump.h>

#include <ptp.h>
#include <ptpdebug.h>
#include <nikon.h>

class CamStateHandlers : public PTPStateHandlers
{
      enum CamStates { stInitial, stDisconnected, stConnected };
      CamStates stateConnected;
    
public:
      CamStateHandlers() : stateConnected(stInitial){};
      
      virtual void OnDeviceDisconnectedState(PTP *ptp);
      virtual void OnDeviceInitializedState(PTP *ptp);
};

class Nikon : public NikonDSLR
{
    uint32_t     nextPollTime;   // Time of the next poll to occure
    
public:
    bool         bPollEnabled;   // Enables or disables camera poll
    bool         bLVEnabled;
    uint32_t     nStep;

    Nikon(USB *pusb, PTPStateHandlers *pstates) : NikonDSLR(pusb, pstates), nextPollTime(0), bPollEnabled(false), bLVEnabled(false), nStep(0)
    { 
    };
    
    virtual uint8_t Poll()
    {
        static bool first_time = true;
        PTP::Poll();
        
        if (!bPollEnabled)
            return 0;
        
        uint32_t  current_time = millis();
        
        if (current_time >= nextPollTime)
        {
            Serial.println("\r\n");
            
            HexDump  hex;
            //GetLiveViewImage(&hex);
            
            nextPollTime = current_time + 1000;
        }
        first_time = false;
        return 0;
    };
};

CamStateHandlers    CamStates;
USB                 Usb;
USBHub              Hub1(&Usb);
Nikon               Nik(&Usb, &CamStates);

void CamStateHandlers::OnDeviceDisconnectedState(PTP *ptp)
{
    PTPTRACE("Disconnected\r\n");
    if (stateConnected == stConnected || stateConnected == stInitial)
    {
        ((Nikon*)ptp)->bPollEnabled = false;
        stateConnected = stDisconnected;
        E_Notify(PSTR("\r\nDevice disconnected.\r\n"),0x80);
    }
}

void CamStateHandlers::OnDeviceInitializedState(PTP *ptp)
{
    if (stateConnected == stDisconnected || stateConnected == stInitial)
    {
        stateConnected = stConnected;
        E_Notify(PSTR("\r\nDevice connected.\r\n"),0x80);
        ((Nikon*)ptp)->bPollEnabled = true;
        
        uint16_t  ret = ptp->Operation(PTP_OC_NIKON_StartLiveView, 0, NULL);
        
        ((Nikon*)ptp)->bLVEnabled = (ret == PTP_RC_OK);
    }
    if (!((Nikon*)ptp)->bLVEnabled)
        return;

    ((Nikon*)ptp)->MoveFocus(((((Nikon*)ptp)->nStep % 10) ? 1 : 2), 64);
    ((Nikon*)ptp)->nStep ++;
    delay(100);
}

void setup() 
{
    Serial.begin( 115200 );
    Serial.println("Start");

    if (Usb.Init() == -1)
        Serial.println("OSC did not start.");

    delay( 200 );
}

void loop() 
{
    Usb.Task();
}


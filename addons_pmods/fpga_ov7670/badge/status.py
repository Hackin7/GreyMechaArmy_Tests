"""Read the camera diagnostic SPI port without controlling the camera."""
import board
import digitalio
import time
def camera_status(verbose=True):
    pins=[]
    try:
        sck=digitalio.DigitalInOut(board.GP8); pins.append(sck)
        miso=digitalio.DigitalInOut(board.GP10); pins.append(miso)
        cs=digitalio.DigitalInOut(board.GP11); pins.append(cs)
        sck.switch_to_output(value=False)
        miso.switch_to_input()
        cs.switch_to_output(value=True)
        cs.value=False
        time.sleep(0.001)
        received=bytearray(116)
        for n in range(116):
            value=0
            for _ in range(8):
                sck.value=True
                value=(value<<1)|int(miso.value)
                sck.value=False
            received[n]=value
        cs.value=True
        assert received[:4]==b'CAM2', 'Camera diagnostic bitstream not running: '+repr(received)
        flags=received[7]
        rates={}
        if received[96:100]==b'COL1':
            rates['raw_color_samples']=[hex(int.from_bytes(received[pos:pos+2],'big'))
                for pos in range(100,116,2)]
        if received[64:68]==b'FPS1':
            for n,key in enumerate(('timing_profile','valid_frames','malformed_frames',
                    'capture_drops','replaced_frames','accepted_frames','display_frames')):
                rates[key]=int.from_bytes(received[68+n*4:72+n*4],'big')
        if verbose and received[32:36]==b'PIN1':
            levels=int.from_bytes(received[36:38],'big')
            changed=int.from_bytes(received[38:40],'big')
            names=('PCLK_A12','VSYNC_A13','HREF_A9','D0_B9','D1_B13',
                'D2_B8','D3_B12','D4_A4','D5_B11','D6_A3','D7_A11','SDA_A10')
            for bit,name in enumerate(names):
                pos=62-bit*2
                print('CAMERA_PIN',name,'level',(levels>>bit)&1,
                    'changed',bool(changed&(1<<bit)),
                    'rising_mod65536',int.from_bytes(received[pos:pos+2],'big'))
        result={'led_bits':hex(received[11]),'reset_released':bool(flags&128),
            'pll_locked':bool(flags&64),'display_ready':bool(flags&32),
            'configured':bool(flags&16),'live':bool(flags&8),
            'frame_valid':bool(flags&4),'malformed':bool(flags&2),
            'active':bool(flags&1),'pid':hex(received[4]),'version':hex(received[5]),
            'last_register':hex(received[6]),'last_result':hex(received[8]),
            'error_code':received[10],
            'nack_mask':hex(received[9]),
            'scan_complete':bool(received[28]&128) if received[10] else None,
            'scan_first_ack_7bit':hex(received[28]&127) if received[10] else None,
            'scan_ack_count':received[29] if received[10] else None,
            'pins_reset_pwdn_xclk_scl_sda_href_vs_pclk':bin(received[30]) if received[10] else None,
            'scan_current_address':hex(received[31]) if received[10] else None,
            'pclk_edges':int.from_bytes(received[12:16],'big'),
            'camera_frames':int.from_bytes(received[16:20],'big'),
            'accepted_frames':int.from_bytes(received[20:24],'big'),
            'display_frames':int.from_bytes(received[24:28],'big'),
            'last_frame_lines':None if received[10] else int.from_bytes(received[28:32],'big')>>22,
            'last_line_bytes':None if received[10] else int.from_bytes(received[28:32],'big')&4095}
        result.update(rates)
        return result
    finally:
        for p in pins: p.deinit()
if __name__=='__main__':
    for _ in range(3):
        print('CAMERA_STATUS',camera_status())
        time.sleep(1)

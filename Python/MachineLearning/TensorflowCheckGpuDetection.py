# Install on Linux: 
#   Check for drivers
#nvidia-smi
#   Double-check GPU install:
#pip install tensorflow[and-cuda]


#Check GPU is detected & which one:

import tensorflow as tf
gpu_devices = tf.config.experimental.list_physical_devices("GPU")
if len(gpu_devices)>0:
    print("GPU(s) detected")
    for gpu in gpu_devices: print(gpu, gpu.name, gpu.device_type)
else: print("NO GPU DETECTED :(")
            

# Title

Tools -> Create and Package new IP
Create a new AXI4 Peripheral
name and the location of the ip are important, we can create a new folder to hold our IPs.
We can write description as well, go next.

We choose Interface Type, can see the explanation if we click to the text.

Lite creates registers, Full creates a BRAM and capable of Burst operations, we work with adresses. Stream, there is no adress work, stream the data basically.

Interface Type Lite
Interface Mode Slave
Number of Registers 4 (minimum we can choose)

Create Peripheral
Choose Edit IP to open the IP project temporarily so that we can create our IP however we want.
Finish.

IP project will be opened and after we implemented it, first synthesize it to see whethere there is a problem and click to the `Package IP`

Now, we are ready to use this IP in our block desing in another project. But first, we need to show our IP folder. Go settings-> IP -> Repository -> Choose the IP folder
Vivado will see the IPs here and in bd when we type we can see our IP.

If we somehow want to edit this IP we can just right click to the block in the called project and choose `Edit in IP Packager`. This will open the project IP implemented. Re-Package IP.










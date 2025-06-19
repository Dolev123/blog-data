# Zig & IoCtl

I stumbled upon a nice piece of software name _evtest_[^1], which, in the very simplest of terms, logs all keyboard events and prints them.
As someone who uses linux both for development and as the main OS, I assumed it was something like reading from the device and parsing the data.
Not something that should be super complicated, but enough interesting and fun to try to implement.
Since I mostly work with golang, c and python, I decided to implement it a a new (to me) language that peaked my interest for some time: zig.
  
## Checking out evtest & Learning about IoCtl

Installed via the package manager (dnf), and ran it as root with sudo, it listed all the devices under '/dev/input/event*', and waited for me to specify one.
strace'ing the program (and filtering on _openat_ and _ioctl_) shows that it just iterates over '/dev/input' and prints to the user. 
I decided instead to use a different approach, I'll touch on that later. 
I ran it again (without strace), but this time on the specific deivce, and I was listed with all the event types and their codes.
Besides that, for every key board event, it printed out it's time, type, code and value:
```txt
...
Event: time 1750357881.796674, type 4 (EV_MSC), code 4 (MSC_SCAN), value 1
Event: time 1750357881.796674, type 1 (EV_KEY), code 29 (KEY_LEFTCTRL), value 1
Event: time 1750357881.796674, -------------- SYN_REPORT ------------
Event: time 1750357881.872062, type 4 (EV_MSC), code 4 (MSC_SCAN), value 2
...
```
Now, in order to know which syscalls are relevant to trace, let's run the program agin, hit a few keys, and look at the summary of strace:
```sh
sudo strace -e trace=c evtest /dev/input/event3 >/dev/null
```
I have filtered the output, and left the ones that seemed more relevant:
```txt
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 35.93    0.005515          43       126           pselect6
 13.77    0.002113          16       127           read
  0.49    0.000075           5        13           ioctl
  0.32    0.000049          16         3           openat
```

Let's go over the different syscalls:
* __pselect6__ : monitors multiple file descriptors, and waits until one of them is ready for read/write. used to wait for events from the devices.
* __openat__: open a path and generate a file descriptor.
* __read__: as read, read the events from the device.
* __ioctl__: interfacing with devices, their drivers and black magic.

_pselect6_ and _read_ are used in conjunction in order to wait and read an event, therefore, are less interesting to trace. 
_openat_ is not really needed to trace also, since we know what the path for the device is, but it will tell us what the relevant fd is.  
Now I'll run the program again, this time tracing _ioctl_ and _openat_. The results:
```txt
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/lib64/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/dev/input/event3", O_RDONLY) = 3
ioctl(1, TCGETS, 0x7fff1ce07190)        = -1 ENOTTY (Inappropriate ioctl for device)
ioctl(3, EVIOCGVERSION, [0x10001])      = 0
ioctl(3, EVIOCGID, {bustype=17, vendor=1, product=1, version=43907}) = 0
ioctl(3, EVIOCGNAME(256), "AT Translated Set 2 keyboard\0") = 29
ioctl(3, EVIOCGBIT(0, 31), [EV_SYN EV_KEY EV_MSC EV_LED ...]) = 8
ioctl(3, EVIOCGBIT(EV_KEY, 767), [KEY_ESC KEY_1 KEY_2 KEY_3 ...]) = 96
ioctl(3, EVIOCGBIT(EV_MSC, 767), [MSC_SCAN]) = 8
ioctl(3, EVIOCGLED(6144), [])           = 8
ioctl(3, EVIOCGBIT(EV_LED, 767), [LED_NUML LED_CAPSL LED_SCROLLL]) = 8
ioctl(3, EVIOCGREP, [250, 33])          = 0
ioctl(3, EVIOCGPROP(248), [])           = 8
ioctl(3, EVIOCGRAB, 1)                  = 0
ioctl(3, EVIOCGRAB, 0)                  = 0
Hello
```

The 'Hello' text is the echo from me typing it, which tells us no ioctls were used for reading it (which makes sense).  
We can see a few different ioctls being used: _EVIOCGVERSION_, _EVIOCGID_, _EVIOCGNAME_, _EVIOCGBIT_, _EVIOCGLED_, _EVIOCGREP_, _EVIOCGPROP_, _EVIOCGRAB_. 
Some of those are instantly apparent to know, such as _EVIOCGNAME_, which saves the devices name in a suplied buffer, but others will require a deeper look. 
  
From searching around the internet, I found a few sites that can assist us with looking:
1. Elixir[^2] - The best site for understanding the linux kernel, because it has all of it's source code.
2. The Linux Kernel[^3] - The __second__ best place to understand the kernel, it's documentation.
3. The source code of _evtest_[^1] from the github project.
4. The source code of _python-evdev_[^4] - a python project that wraps ineracting with devices.
  
Looking at 'include/uapi/linux/input-event-types.h', lines 38-51, we can see all the different event types for an "input" device event. 
One of those types is _EV_KEY_, which, as explained by the documentation, \`Used to describe state changes of __keyboards__, buttons, or other key-like devices.\`. 
The documentation also tells us that the values for _EV_KEY_ are: 0 => key released, 1 => key pressed, 2 => repeated press (without releasing key). 
The different keys are specified in the same file, in lines 75-813, which is a lot of keys, even with all the comments and aliasing, which means not all are used at all times. 

In order to see which keys are possible to get, let's search for the part of _evtest_ that displays it at the start (based on the string "Event code "), which sends us to line 1002:
```c
...
static int print_device_info(int fd)
{
...
    char name[256] = "Unknown";
	unsigned long bit[EV_MAX][NBITS(KEY_MAX)];
...
    ioctl(fd, EVIOCGNAME(sizeof(name)), name);
	printf("Input device name: \"%s\"\n", name);

	memset(bit, 0, sizeof(bit));
	ioctl(fd, EVIOCGBIT(0, EV_MAX), bit[0]);
	printf("Supported events:\n");

	for (type = 0; type < EV_MAX; type++) {
		if (test_bit(type, bit[0]) && type != EV_REP) {
			printf("  Event type %d (%s)\n", type, typename(type));
			if (type == EV_SYN) continue;
			ioctl(fd, EVIOCGBIT(type, KEY_MAX), bit[type]);
			for (code = 0; code < KEY_MAX; code++)
				if (test_bit(code, bit[type])) {
					printf("    Event code %d (%s)\n", code, codename(type, code));
					if (type == EV_ABS)
						print_absdata(fd, code);
				}
		}
	}
...
}...
```
[^5]  
Before disecting the code, we can see that our assumption about _EVIOCGNAME_ is correct.  
We can see an array of long (pun intended) arrays of size _KEY_MAX_ bits stroed in long cells. And we can see that _EVIOCGBIT_ is invoked a couple of times against that array.  
Let's follow it's trace inside the kernel code:
```c
// defined at: include/uapi/linux/input.h:178
#define EVIOCGBIT(ev,len)	_IOC(_IOC_READ, 'E', 0x20 + (ev), len)	/* get event bits */

// used in: drivers/input/evdev.c:1197
static long evdev_do_ioctl(struct file *file, unsigned int cmd,
			   void __user *p, int compat_mode)
{
...
	if (_IOC_DIR(cmd) == _IOC_READ) {
        if ((_IOC_NR(cmd) & ~EV_MAX) == _IOC_NR(EVIOCGBIT(0, 0)))
			return handle_eviocgbit(dev,
						_IOC_NR(cmd) & EV_MAX, size,
						p, compat_mode);
...
    }
...
}

// => handle_eviocgbit implemented at: drivers/input/evdev.c:776
static int handle_eviocgbit(struct input_dev *dev,
			    unsigned int type, unsigned int size,
			    void __user *p, int compat_mode)
{
...
	switch (type) {
...
	case EV_KEY: bits = dev->keybit; len = KEY_MAX; break;
...
	return bits_to_user(bits, len, size, p, compat_mode);
}

// dev->keybit defined at: include/linux/input.h:146
/**
 * @keybit: bitmap of keys/buttons this device has
 */
struct input_dev {
...
	unsigned long keybit[BITS_TO_LONGS(KEY_CNT)];
...
}

```
All of that code tells us that the _EVIOCGBIT_ returns an array of bits that corresponds for all the keys active in the device, indicated by 1 (active) and 0 (inactive). 
Therefore, all the relevant keys can be recieved before reading the device. 
That is nice, but I decided to skip this check/info dump, and just listen to the events and translating the keys. 
Skimming in a similar fashion through the other ioctls leads to the conclusion that they're not important for us.  

Now we know which ioctls to call, but we still need to understand __how__ to call them, and better our understanding to __what__ reading the device will give us.

### Deeper look into IoCtls and Input Devices

Using the holy grale _man_ on _ioctl_ tells us what we could have realised from reading _evtest_'s code: 
_ioctl()_ accepts a file descriptor (_fd_) for the device, an operations (_op_) which specifeis what we want to invoke and, sometimes, a pointer for transferring data (_argp_). 
_fd_ is an int, _argp_ is a pointer of our choosing (the same as void*), and _op_ can be constructed with the _\_IOC_ macro from "include/uapi/asm-generic/ioctl.h:69":
```c

#define _IOC(dir,type,nr,size) \
	(((dir)  << _IOC_DIRSHIFT) | \
	 ((type) << _IOC_TYPESHIFT) | \
	 ((nr)   << _IOC_NRSHIFT) | \
	 ((size) << _IOC_SIZESHIFT))
```
But most of the time there is a macro that wraps it, such as _EVIOCGNAME_ (from include/uapi/linux/input.h:142):
```c
#define EVIOCGNAME(len)		_IOC(_IOC_READ, 'E', 0x06, len)		/* get device name */
```
Here we can see that it is a read operation (value 2), with event number 0x06, with some length (which will be the suplied buffer's length), and of type 'E'. __'E'__. HUH?! TF is that?!  

In the wild world of ioctls, anyone can define it's own _type_ indicator, for whatever device one is working on. 
The value is (theoretically) \`completely arbitrary\`[^6], but from the documentation[^7] we can find what it means:
```txt
Code   Seq#(hex)  Include File     Comments
========================================================
...
'E'    all        linux/input.h	   conflict!
'E'    00-0F      xen/evtchn.h	   conflict!
...
```
Ah, it is a conflict device! Wait, that doesn't seem correct...  
It is mostly used as an input device (keyboard/mouse), BUT can be used also for the XEN virtual enviroment.  
  
Now we know what to __send__, and the only thing left is to see what is recieved when we read an event from the device.  
This is quite easy, since it is documented in the source code (include/uapi/linux/input.h:28):
```c
struct input_event {
#if (__BITS_PER_LONG != 32 || !defined(__USE_TIME_BITS64)) && !defined(__KERNEL__)
	struct timeval time;
#define input_event_sec time.tv_sec
#define input_event_usec time.tv_usec
#else
	__kernel_ulong_t __sec;
#if defined(__sparc__) && defined(__arch64__)
	unsigned int __usec;
	unsigned int __pad;
#else
	__kernel_ulong_t __usec;
#endif
#define input_event_sec  __sec
#define input_event_usec __usec
#endif
	__u16 type;
	__u16 code;
	__s32 value;
};
```

Which can be shrinked down to:
```c
struct input_event {
    struct timeval {
        __kernel_old_time_t	tv_sec;		/* seconds */
        __kernel_suseconds_t	tv_usec;	/* microseconds */
    };
	__u16 type;
	__u16 code;
	__s32 value;
};
```

All the required knowledge has been acquired, let's proceed to learning zig!  

## Learning Zig!

My knowledge about the zig language was comprised of:
* It is a low-level systems language.
* It has a good wrapper/interaction with C.
* Instead of having a preprocessor like C, the normal language is used for compile-time flow/logic.
* It is still under development.
  
I downloaded the latest version that was offered to me via my distro (fedora 42 -> zig 0.14.0), and opened 
the (language reference)[https://ziglang.org/documentation/0.14.0/] and the (std documentation)[https://ziglang.org/documentation/0.14.0/std/].  
There were some code examples listed in the site, but I found them not really usefull or educative. 
They present very few use cases for zig, and in my opinion not very relevant ones. 
That said, there are references to other, very good, resources to learn zig from (such as Ziglings[^8] and zig.guide[^9]), which I haven't started with (do not be me).  

I started reading most of the language reference, while trying and testing a small program along the way.
The program's purpose was to implement some very basic parts from our general goal of logging keyboard events. 
Printing to stdout was quite easy, and so was creating variables/consts, importing modules and at this point the code was quite readable. 
But as someone that was used to C, __alot__ of things were __very__ different, and it was hard to adapt.
So I'll go over all the points that stumbled me:

**_struct_ vs _packed struct_**:  
who knew that structs could be orgenized as the compiler wish, and not as I wrote them? 
At hindsight, the fact that I need to specifiy that the order matters, makes sense, because it is not relevant for a substantial amount of cases.  
Also, the size of a _packed struct_ may be larger (alligned) than what have been specified.  
  
**strings are wierd**:  
Apparently, strings are a compile time object, and everything else is just and array/slice/pointer to _u8_. 
Somehow it is exactly like C, and very different from C at the same time. 
The way I wrap my head around it is that "strings" are compile time literals and "null terminated arrays" are for runtime variables/consts.  
  
**arrays and pointers (and slices) are wierder**:  
Why does every byte shoukd have it's own kind of reference value?! 
You can specify about 8 different types that can conceptually be _void*_ in C. 
I still do not fully understand the minute differences, and it can sometimes be a P.I.T.A to figure out which one is the correct one.  
  
**no default allocators**:  
One cannot just _malloc_ and _free_ for his heart's desire, but must create and supply an allocator for each function that requires one. 
At first it was non-intuitive, but after reading about the 4 builtin allocators, and their examples from zig.guide, it all clicked.  
  
**@here(@there(@every(where)))**:  
Since zig is a very strict in what the compiler allows and forbids, it forces everything to be very specific and verbose. 
Most of the time, it is not an issue, but sometimes, a simple task such as printing an _usize_ as _i32_ can take 5 function calls. 
e.g.:
```zig
// ...
    const ret : usize = func_returns_usize();
    if (ret < 0) {
        error_("ioctl EVIOCGNAME error_code: {d} | errno: {}", .{
            @as(i32, @bitCast(@as(u32, @truncate(ret)))),
            std.posix.errno(ret),
        });
        return;
    }
// ...
```
It's probabble that a simpler way exists, but it was not obviuos at the time of writing.  
  
**no enum aliasing**:  
In C, you can have an enum that have 2 names with the same value, and also self reference other values from the enum:
```c
typedef enum E {
    E1,
    E2,
    E3=1,
    E4=E2+1,
} E;
```
In zig it is not possible. 
Which is annoying, because many OS level functions can use the same values with a similar context, and the different names are more readable: 
```c
typedef enum E {
    EBASE,
    E1=EBASE,
    E2,
    ...
    EMAX,
    E_COUNT=EMAX+1,
} E;
```  

**STD not documented**:  
The standart library is not very documented, and the staff that is documented, more often than not, is not documented well enough. 
It was sometimes more understandable to read someone else's code on github, than to consult the std documentation. 
And that's a shame in my opinion.  
  
  
Although I had many things to criticize, I also enjoed many other features of the language, such as:
* Arbitrary sized variables (_u1_, _u9_, _u6500_).
* _comptime_ is very powerfull, and very intuitively integrated into functions.
* Error handling is very easy, but also can be very precise. Also, errors as enums is very nice.
* importing and building is very easy, even without diving deep into the uild system.
* _defer_ is a always good to have, I like it.
* and many more features...

## Overall Thoughts

To summarize, those were a couple of fun hours over the past days. 
I still maintain the view that learning a new language should be through trying to do something practical (and possibly new), 
but it would have been a lot easier if I had just approached it in a more standart way. 
There was a large amount of debugging, going through source code and documentation and a substantial amount of coffee. 
And it was all worth it!  
  
I'm sure I'll have another zig project (or expand the current one) in the future. 
And I know this will not be my last time working with ioctls...  
  
Anyway, if you want to check the fruit of my labor, feel free to (do so)[https://github.com/Dolev123/zig-keypresses].

## Footnotes

[^1] https://github.com/freedesktop-unofficial-mirror/evtest/
[^2] https://elixir.bootlin.com/linux/v6.14/source (I referenced the same kernel version that is on my machine).
[^3] specifically https://docs.kernel.org/driver-api/ioctl.html and https://docs.kernel.org/input/event-codes.html
[^4] the main file of interest is https://github.com/gvalkov/python-evdev/blob/main/src/evdev/input.c
[^5] https://github.com/freedesktop-unofficial-mirror/evtest/blob/master/evtest.c#L1002
[^6] run _man ioctl_, and jump to the NOTES section. 
[^7] https://docs.kernel.org/userspace-api/ioctl/ioctl-number.html or https://www.kernel.org/doc/Documentation/ioctl/ioctl-number.txt
[^8] https://codeberg.org/ziglings/exercises/#ziglings
[^9] https://zig.guide/

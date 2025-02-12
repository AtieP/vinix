module fbdev

import ioctl
import resource
import fs
import stat
import klock
import event.eventstruct
import dev.fbdev.api

pub struct FramebufferNode {
pub mut:
	stat         stat.Stat
	refcount     int
	l            klock.Lock
	event        eventstruct.Event
	status       int
	can_mmap     bool
	node_lock  	 klock.Lock
	initialized  bool
	node_created bool
	info         api.FramebufferInfo
}

const fbdev_max_device_count = 32

__global (
	fbdev_lock  klock.Lock
	fbdev_nodes [fbdev_max_device_count]FramebufferNode
)

fn (mut this FramebufferNode) mmap(page u64, flags int) voidptr {
	offset := page * page_size

	if offset >= this.info.size {
		return voidptr(0)
	}

	unsafe {
		return voidptr(u64(this.info.base) + offset - higher_half)
	}
}

fn (mut this FramebufferNode) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 {
		return i64(0)
	}

	vmem := &u8(this.info.base)
	mut actual_count := count

	if loc + count > this.info.size {
		actual_count = count - ((loc + count) - this.info.size)
	}

	unsafe { C.memcpy(buf, &vmem[loc], actual_count) }

	return i64(actual_count)
}

fn (mut this FramebufferNode) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 {
		return i64(0)
	}

	vmem := &u8(this.info.base)
	mut actual_count := count

	if loc + count > this.info.size {
		actual_count = count - ((loc + count) - this.info.size)
	}

	unsafe { C.memcpy(&vmem[loc], buf, actual_count) }

	return i64(actual_count)
}

fn (mut this FramebufferNode) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	match request {
		ioctl.fbioget_vscreeninfo {
			unsafe { C.memcpy(argp, &this.info.variable, sizeof(api.FBVarScreenInfo)) }
			return 0
		}
		ioctl.fbioget_fscreeninfo {
			unsafe { C.memcpy(argp, &this.info.fixed, sizeof(api.FBFixScreenInfo)) }
			return 0
		}
		else {
			return resource.default_ioctl(handle, request, argp)
		}
	}
}

fn (mut this FramebufferNode) unref(handle voidptr) ? {
	this.refcount--
}

fn (mut this FramebufferNode) grow(handle voidptr, new_size u64) ? {
}

fn create_device_node(index u64) ? {
	if index >= fbdev_max_device_count {
		return error('device index out of range')
	}

	mut node := unsafe { &fbdev_nodes[index] }

	if node.node_created {
		return
	}

	node.stat.size = 0
	node.stat.blocks = 0
	node.stat.blksize = 4096
	node.stat.rdev = resource.create_dev_id()
	node.stat.mode = 0o666 | stat.ifchr
	node.can_mmap = true
	node.node_created = true

	fs.devtmpfs_add_device(node, 'fb${index}')
	println('fbdev: created device node /dev/fb${index}')
}

pub fn register_device(info api.FramebufferInfo) ? {
	mut index := u64(0)

	fbdev_lock.acquire()
	defer {
		fbdev_lock.release()
	}

	for index < fbdev_max_device_count {
		if fbdev_nodes[index].initialized {
			index += 1
			continue
		}

		fbdev_nodes[index].info = info
		fbdev_nodes[index].initialized = true
		break
	}

	if index >= fbdev_max_device_count {
		return error('too many registered devices')
	}

	println('fbdev: registered new framebuffer device (using driver ${info.driver.name} and mode ${info.variable.xres}x${info.variable.yres}x${info.variable.bits_per_pixel})')

	return create_device_node(index)
}

pub fn register_driver(driver &api.FramebufferDriver) {
	unsafe {
		driver.register_device = register_device
		driver.init()
	}
}

pub fn initialise() {

}
module console

import x86.idt
import x86.apic
import x86.kio
import event
import klock
import sched

const max_scancode = 0x57
const capslock = 0x3a
const left_alt = 0x38
const left_alt_rel = 0xb8
const right_shift = 0x36
const left_shift = 0x2a
const right_shift_rel = 0xb6
const left_shift_rel = 0xaa
const ctrl = 0x1d
const ctrl_rel = 0x9d

const console_buffer_size = 1024
const console_bigbuf_size = 4096

__global (
	console_read_lock klock.Lock
	console_event event.Event
	console_capslock_active = bool(false)
	console_shift_active = bool(false)
	console_ctrl_active = bool(false)
	console_alt_active = bool(false)
	console_extra_scancodes = bool(false)
	console_buffer [console_buffer_size]byte
	console_buffer_i = u64(0)
	console_bigbuf [console_bigbuf_size]byte
	console_bigbuf_i = u64(0)
)

const convtab_capslock = [
	`\0`, `\e`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `0`, `-`, `=`, `\b`, `\t`,
	`Q`, `W`, `E`, `R`, `T`, `Y`, `U`, `I`, `O`, `P`, `[`, `]`, `\n`, `\0`, `A`, `S`,
	`D`, `F`, `G`, `H`, `J`, `K`, `L`, `;`, `'`, `\``, `\0`, `\\`, `Z`, `X`, `C`, `V`,
	`B`, `N`, `M`, `,`, `.`, `/`, `\0`, `\0`, `\0`, ` `
]

const convtab_shift = [
	`\0`, `\e`, `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `(`, `)`, `_`, `+`, `\b`, `\t`,
	`Q`, `W`, `E`, `R`, `T`, `Y`, `U`, `I`, `O`, `P`, `{`, `}`, `\n`, `\0`, `A`, `S`,
	`D`, `F`, `G`, `H`, `J`, `K`, `L`, `:`, `"`, `~`, `\0`, `|`, `Z`, `X`, `C`, `V`,
	`B`, `N`, `M`, `<`, `>`, `?`, `\0`, `\0`, `\0`, ` `
]

const convtab_shift_capslock = [
	`\0`, `\e`, `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `(`, `)`, `_`, `+`, `\b`, `\t`,
	`q`, `w`, `e`, `r`, `t`, `y`, `u`, `i`, `o`, `p`, `{`, `}`, `\n`, `\0`, `a`, `s`,
	`d`, `f`, `g`, `h`, `j`, `k`, `l`, `:`, `"`, `~`, `\0`, `|`, `z`, `x`, `c`, `v`,
	`b`, `n`, `m`, `<`, `>`, `?`, `\0`, `\0`, `\0`, ` `
]

const convtab_nomod = [
	`\0`, `\e`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `0`, `-`, `=`, `\b`, `\t`,
	`q`, `w`, `e`, `r`, `t`, `y`, `u`, `i`, `o`, `p`, `[`, `]`, `\n`, `\0`, `a`, `s`,
	`d`, `f`, `g`, `h`, `j`, `k`, `l`, `;`, `'`, `\``, `\0`, `\\`, `z`, `x`, `c`, `v`,
	`b`, `n`, `m`, `,`, `.`, `/`, `\0`, `\0`, `\0`, ` `
]

fn is_printable(c byte) bool {
	return (c >= 0x20 && c <= 0x7e)
}

fn add_to_buf_char(c byte) {
	console_read_lock.acquire()

	match c {
		`\n` {
			if console_buffer_i == console_buffer_size {
				console_read_lock.release()
				return
			}
			console_buffer[console_buffer_i] = c
			console_buffer_i++
			//if console_termios.c_lflag & ECHO != 0 {
				print('${c:c}')
			//}
			for i := u64(0); i < console_buffer_i; i++ {
				if console_bigbuf_i == console_bigbuf_size {
					console_read_lock.release()
					return
				}
				console_bigbuf[console_bigbuf_i] = console_buffer[i]
				console_bigbuf_i++
			}
			console_buffer_i = 0
			console_read_lock.release()
			return
		}
		`\b` {
			if console_buffer_i == 0 {
				console_read_lock.release()
				return
			}
			console_buffer_i--
			console_buffer[console_buffer_i] = 0
			//if console_termios.c_lflag & ECHO != 0 {
				print('\b \b')
			//}
			console_read_lock.release()
			return
		}
		else {}
	}

	//if console_termios.c_lflag & ICANON != 0 {
		if console_buffer_i == console_buffer_size {
			console_read_lock.release()
			return
		}
		console_buffer[console_buffer_i] = c
		console_buffer_i++
	//}

	if is_printable(c) /* && console_termios.c_lflag & ECHO != 0 */ {
		print('${c:c}')
	}

	console_read_lock.release()
	return
}

fn add_to_buf(ptr &byte, count u64) {
	for i := u64(0); i < count; i++ {
		unsafe { add_to_buf_char(ptr[i]) }
	}
	console_event.trigger()
}

fn keyboard_handler() {
	vect := idt.allocate_vector()

	print('console: PS/2 keyboard vector is 0x${vect:x}\n')

	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, vect, 1, true)

	for {
		mut which := u64(0)
		event.await([&int_events[vect]], &which, true)
		input_byte := kio.inb(0x60)

		if input_byte == 0xe0 {
			console_extra_scancodes = true
			continue
		}

		if console_extra_scancodes == true {
			console_extra_scancodes = false

			match input_byte {
				ctrl {
					console_ctrl_active = true
					continue
				}
				ctrl_rel {
					console_ctrl_active = false
					continue
				}
				else {}
			}
		}

		match input_byte {
			left_alt {
				console_alt_active = true
				continue
			}
			left_alt_rel {
				console_alt_active = false
				continue
			}
			left_shift,
			right_shift {
				console_shift_active = true
				continue
			}
			left_shift_rel,
			right_shift_rel {
				console_shift_active = false
				continue
			}
			ctrl {
				console_ctrl_active = true
				continue
			}
			ctrl_rel {
				console_ctrl_active = false
				continue
			}
			capslock {
				console_capslock_active = !console_capslock_active
				continue
			}
			else {}
		}

		mut c := byte(0)
		if input_byte < max_scancode {
			if console_capslock_active == false && console_shift_active == false {
				c = convtab_nomod[input_byte]
			}
			if console_capslock_active == false && console_shift_active == true {
				c = convtab_shift[input_byte]
			}
			if console_capslock_active == true && console_shift_active == false {
				c = convtab_capslock[input_byte]
			}
			if console_capslock_active == true && console_shift_active == true {
				c = convtab_shift_capslock[input_byte]
			}
		} else {
			continue
		}

		add_to_buf(&c, 1)
	}
}

pub fn initialise() {
	sched.new_kernel_thread(voidptr(keyboard_handler), voidptr(0), true)
}

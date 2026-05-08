#include <linux/module.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/io.h>

#define DEVICE_NAME "total_shield"
#define CLASS_NAME "total_shield_class"
#define BASE_ADDR 0x43C00000  // AXI base address (adjust for your system)
#define REG_CONTROL   0x00
#define REG_STATUS    0x04
#define REG_THRESHOLD 0x08
#define REG_ALARM     0x0C
#define REG_SNAPSHOT  0x10

static int major_number;
static struct class* shield_class = NULL;
static struct device* shield_device = NULL;
static void __iomem *shield_base;

// Open device
static int dev_open(struct inode *inodep, struct file *filep) {
    printk(KERN_INFO "TOTAL Shield: device opened\n");
    return 0;
}

// Read from register
static ssize_t dev_read(struct file *filep, char __user *buffer, size_t len, loff_t *offset) {
    u32 reg_val;
    if (len != sizeof(u32)) return -EINVAL;
    switch (*offset) {
        case 0: reg_val = ioread32(shield_base + REG_STATUS); break;
        case 1: reg_val = ioread32(shield_base + REG_ALARM); break;
        default: return -EINVAL;
    }
    if (copy_to_user(buffer, &reg_val, sizeof(u32))) return -EFAULT;
    return sizeof(u32);
}

// Write to register (requires token)
static ssize_t dev_write(struct file *filep, const char __user *buffer, size_t len, loff_t *offset) {
    u32 value;
    if (len != sizeof(u32)) return -EINVAL;
    if (copy_from_user(&value, buffer, sizeof(u32))) return -EFAULT;
    iowrite32(value, shield_base + REG_CONTROL);
    return sizeof(u32);
}

// File operations
static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = dev_open,
    .read = dev_read,
    .write = dev_write,
};

static int __init shield_init(void) {
    // Allocate major number
    major_number = register_chrdev(0, DEVICE_NAME, &fops);
    if (major_number < 0) return major_number;
    
    // Create device class
    shield_class = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(shield_class)) {
        unregister_chrdev(major_number, DEVICE_NAME);
        return PTR_ERR(shield_class);
    }
    
    // Create device
    shield_device = device_create(shield_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
    if (IS_ERR(shield_device)) {
        class_destroy(shield_class);
        unregister_chrdev(major_number, DEVICE_NAME);
        return PTR_ERR(shield_device);
    }
    
    // Map AXI memory
    shield_base = ioremap_nocache(BASE_ADDR, 0x1000);
    if (!shield_base) {
        device_destroy(shield_class, MKDEV(major_number, 0));
        class_destroy(shield_class);
        unregister_chrdev(major_number, DEVICE_NAME);
        return -ENOMEM;
    }
    
    printk(KERN_INFO "TOTAL Shield driver loaded at 0x%lx\n", (unsigned long)shield_base);
    return 0;
}

static void __exit shield_exit(void) {
    iounmap(shield_base);
    device_destroy(shield_class, MKDEV(major_number, 0));
    class_destroy(shield_class);
    unregister_chrdev(major_number, DEVICE_NAME);
    printk(KERN_INFO "TOTAL Shield driver unloaded\n");
}

module_init(shield_init);
module_exit(shield_exit);

MODULE_LICENSE("Proprietary");
MODULE_AUTHOR("TOTAL Protocol Labs");
MODULE_DESCRIPTION("Driver for TOTAL Shield hardware security module");

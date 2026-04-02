#include <linux/module.h>
#include <linux/init.h>
#include <linux/errno.h>
#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/miscdevice.h>
#include <linux/slab.h>
#include <linux/io.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include "vga_ball.h"

#define DRIVER_NAME "vga_ball"

#define BALL_POSITION(x) (x)

struct vga_ball_dev {
	struct resource res;
	void __iomem *virtbase;
	/* last position we pushed to hardware so READ_POSITION has something to return */
	vga_ball_position_t position;
} dev;

static void sanitize_position(vga_ball_position_t *position)
{
	/* keep software on the visible screenk */
	if (position->x > 639)
		position->x = 639;
	if (position->y > 479)
		position->y = 479;
}

static void write_position(vga_ball_position_t *position)
{
	u32 regval;

	sanitize_position(position);
	/* hardware expects y in the top half and x in the bottom half */
	regval = ((u32) position->y << 16) | position->x;
	iowrite32(regval, BALL_POSITION(dev.virtbase));
	dev.position = *position;
}

static long vga_ball_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
	vga_ball_position_t position;

	switch (cmd) {
	case VGA_BALL_WRITE_POSITION:
		/* userspace hands us the next ball center */
		if (copy_from_user(&position, (vga_ball_position_t *) arg,
				   sizeof(vga_ball_position_t)))
			return -EACCES;
		write_position(&position);
		break;

	case VGA_BALL_READ_POSITION:
		/*  report the last value we stored */
		position = dev.position;
		if (copy_to_user((vga_ball_position_t *) arg, &position,
				 sizeof(vga_ball_position_t)))
			return -EACCES;
		break;

	default:
		return -EINVAL;
	}

	return 0;
}

static const struct file_operations vga_ball_fops = {
	.owner		= THIS_MODULE,
	.unlocked_ioctl = vga_ball_ioctl,
};

static struct miscdevice vga_ball_misc_device = {
	.minor		= MISC_DYNAMIC_MINOR,
	.name		= DRIVER_NAME,
	.fops		= &vga_ball_fops,
};

static int __init vga_ball_probe(struct platform_device *pdev)
{
	vga_ball_position_t center = { 320, 240 };
	int ret;

	/* register /dev/vga_ball first so userspace has something to open */
	ret = misc_register(&vga_ball_misc_device);
	if (ret)
		return ret;

	ret = of_address_to_resource(pdev->dev.of_node, 0, &dev.res);
	if (ret) {
		ret = -ENOENT;
		goto out_deregister;
	}

	if (request_mem_region(dev.res.start, resource_size(&dev.res),
			       DRIVER_NAME) == NULL) {
		ret = -EBUSY;
		goto out_deregister;
	}

	dev.virtbase = of_iomap(pdev->dev.of_node, 0);
	if (dev.virtbase == NULL) {
		ret = -ENOMEM;
		goto out_release_mem_region;
	}

	/* start in the midle so the first frame looks alright */
	write_position(&center);

	return 0;

out_release_mem_region:
	release_mem_region(dev.res.start, resource_size(&dev.res));
out_deregister:
	misc_deregister(&vga_ball_misc_device);
	return ret;
}

static int vga_ball_remove(struct platform_device *pdev)
{
	iounmap(dev.virtbase);
	release_mem_region(dev.res.start, resource_size(&dev.res));
	misc_deregister(&vga_ball_misc_device);
	return 0;
}

#ifdef CONFIG_OF
static const struct of_device_id vga_ball_of_match[] = {
	{.compatible = "csee4840,vga_ball-1.0" },
	{},
};
MODULE_DEVICE_TABLE(of, vga_ball_of_match);
#endif

static struct platform_driver vga_ball_driver = {
	.driver	= {
		.name	= DRIVER_NAME,
		.owner	= THIS_MODULE,
		.of_match_table = of_match_ptr(vga_ball_of_match),
	},
	.remove	= __exit_p(vga_ball_remove),
};

static int __init vga_ball_init(void)
{
	pr_info(DRIVER_NAME ": init\n");
	return platform_driver_probe(&vga_ball_driver, vga_ball_probe);
}

static void __exit vga_ball_exit(void)
{
	platform_driver_unregister(&vga_ball_driver);
	pr_info(DRIVER_NAME ": exit\n");
}

module_init(vga_ball_init);
module_exit(vga_ball_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Stephen A. Edwards, Columbia University");
MODULE_DESCRIPTION("VGA ball driver");


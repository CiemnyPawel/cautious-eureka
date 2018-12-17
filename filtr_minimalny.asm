.data
idInput:	.word	0
idOutput:	.word	0
padding:	.word	0
buf:		.space 	55000		# 2000 * 3 * 9 (2000 - max. width, 3 - three colors per pixel, each need 1 byte, 9 - max. mask )
outBuf:		.space	6100
pad:		.space	3
inputMess:	.asciiz "Name of input file\n"
outputMess:	.asciiz "Name of output file\n"
maskSize:	.asciiz "Size of filter mask\n"
inputFile:	.space	128
outputFile:	.space	128
.text
main:
	li 	$v0, 	4
	la 	$a0, 	maskSize
	syscall
	li 	$v0, 	5
	syscall

	move 	$s2, 	$v0			# $s0 and $s1 will be used later for filedescriptor
	li 	$v0, 	4
	la 	$a0, 	inputMess
	syscall

	li	$v0,	8
	la	$a0,	inputFile
	li	$a1,	120
	syscall

	li 	$v0, 	4
	la 	$a0, 	outputMess
	syscall

	li	$v0,	8
	la	$a0,	outputFile
	li	$a1,	120
	syscall

	li $t0, 0

inputCorrection:
	lb $t2, inputFile($t0)
	addiu $t0, $t0, 1			#incrementing as long as it finds '\n'
	bne $t2, '\n' , inputCorrection

	#after we find it :
	subiu $t0, $t0, 1			#the actual change we're making
	sb $zero, inputFile($t0)
	li $t0, 0

outputCorrection:
	lb $t2, outputFile($t0)
	addiu $t0, $t0, 1			#incrementing as long as it finds '\n'
	bne $t2, '\n' , outputCorrection
	#after we find it :
	subiu $t0, $t0, 1			#the actual change we're making
	sb $zero, outputFile($t0)


#read_infile_header:

	li	$v0,	13			# open file
	la	$a0,	inputFile
	li	$a1,	0			# read-only
	syscall
	move	$s0,	$v0			# move the file descriptor to s0, since we don't need its name any longer
	bltz	$s0,	quit			# error

	li	$v0,	14			# read its header
	move	$a0,	$s0
	la	$a1,	buf+2			# so that we read from buf addresses aligend to 4 bytes
	li	$a2,	54
	syscall
	bne	$v0,	54,	close_in	# error

	lh	$t0,	buf+16
	bne	$t0,	40,	close_in	# bitmapinfoheader size error

	lw	$s3,	buf+20			# width
	lw	$s4,	buf+24			# height

	bgt	$s3,	2000,	close_in	# max width error
	lh	$t0,	buf+2
	bne	$t0,	0x4D42,	close_in	# signature error
	lw	$t0,	buf+8
	bnez	$t0,	quit			# must-be-zero error


	lw	$t0,	buf+12			# offset to pixel array
	move	$a0,	$s0			# load what is left between header and pixel array
	la	$a1,	buf+56
	sub	$a2,	$t0,	54		# a0 already contains file descriptor and a1 the address of the image buffer
	li	$v0,	14			# read till the beginning of the pixel array
	syscall

	li	$v0,	13			# open and create the outfile
	la	$a0,	outputFile
	li	$a1,	9
	syscall
	move	$s1,	$v0
	bltz	$s1,	quit			# opening file for writing error

	li	$v0,	15			# write header and bitmapinfoheader
	move	$a0,	$s1
	la	$a1,	buf+2
	move	$a2,	$t0
	syscall
	bne	$v0,	$t0,	quit		# write to file error


	mul	$t0,	$s3,	3		# calculate padding
	li	$t1,	4
	div	$t0,	$t1
	mfhi	$s5				# remainder
	beqz	$s5,	calculate_max_box
	sub	$s5,	$t1,	$s5

calculate_max_box:
	blez	$s2,	quit			# no need to go through the filtering algorithm if the box size is <= 0
	mul	$t0,	$s3,	3
	addu	$t0,	$t0,	$s5
	mul	$t0,	$t0,	$s2
	li	$t1,	55000
	bgt	$t0,	$t1,	quit		# the max box size for a given image equals buffer_size/(3*width+padding)


# s0 - infile descr, s1 - outfile descr, s2 - box size, s3 - width, s4 - height, s5 - padding in Bytes

	li	$t0,	0
	move	$a0,	$s0

read_initial_rows:
	# read the first box rows of the bmp file into the buffer
	li	$v0,	14			# read row data
	mul	$t1,	$s3,	3
	mul	$t1,	$t1,	$t0		# calculate adress for new row in buffer (3*width)*(index_of_row)
	la	$a1,	buf($t1)
	move	$a2,	$s3
	mul	$a2,	$a2,	3
	syscall
	# if end of file ( $v0 == 0 ) was read then this means there are less than box rows and we need to end loop
	beqz	$v0,	filter_prep
	bne	$v0,	$a2,	quit		# error

	li	$v0,	14			# read padding
	la	$a1,	pad
	move	$a2,	$s5
	syscall
	bne	$v0,	$s5,	quit		# error

	move	$s6,	$t0
	addiu	$t0,	$t0,	1
	blt	$t0,	$s2,	read_initial_rows

filter_prep:
# s0 - width, s1 - height, s2 - boxsize, s3 - index of top row,
# s4, s5, s6 - BGR, s7 - half of boxsize


# t0 - X column number of the filtered pixel, t1 - Y its row number
# t2 - minX checked column, t3 - maxX checked column for filtered pixel
# t4 - minY checked row, t5 - maxY checked row
# t6 - X column of the currently checked pixel t7 - Y its row

	sw	$s0,	idInput
	sw	$s1,	idOutput
	sw	$s5,	padding
	move	$s0,	$s3			#width
	move	$s1,	$s4			#height
	move	$s3,	$s6			#index of top row
	div	$s7,	$s2,	2		#half of box size
	
	li	$t0,	0
	li	$t1,	0
	li	$t2,	0
	li	$t3,	0
	li	$t4,	0
	li	$t5,	0
	li	$t6,	0
	li	$t7,	0
min_Y_c:
	sub	$t4,	$t1,	$s7
	bgez	$t4,	max_Y_c
	li	$t4,	0
max_Y_c:
	add	$t5,	$t1,	$s7
	blt	$t5,	$s1,	min_X_c
	subiu	$t5,	$s1,	1
min_X_c:
	sub	$t2,	$t0,	$s7
	bgez	$t2,	max_X_c
	li	$t2,	0
max_X_c:
	add	$t3,	$t0,	$s7
	blt	$t3,	$s0,	init_RGB
	subiu	$t3,	$s0,	1
init_RGB:
	li	$s4,	255	#B
	li	$s5,	255	#G
	li	$s6,	255	#R
init_Y:
	move	$t7,	$t4
init_X:
	move	$t6,	$t2
locate_pixel_in_box:
	div	$t7,	$s2
	mfhi	$t8
	mul	$t8,	$t8,	$s0
	addu	$t8,	$t8,	$t6
	mul	$t8,	$t8,	3
check_B:
	lbu	$t9,	buf($t8)
	bge	$t9,	$s4,	check_G
	move	$s4,	$t9
check_G:
	addiu	$t8, 	$t8,	1
	lbu	$t9,	buf($t8)
	bge	$t9,	$s5,	check_R
	move	$s5,	$t9
check_R:
	addiu	$t8, 	$t8,	1
	lbu	$t9,	buf($t8)
	bge	$t9,	$s6,	check_next_pixel
	move	$s6,	$t9
check_next_pixel:
	addiu	$t6,	$t6,	1
	addiu	$t8,	$t8,	1
	ble	$t6,	$t3,	check_B
	addiu	$t7,	$t7,	1
	ble	$t7,	$t5,	init_X
save_pixel:
	#minRGB is now found, the only job left to do is now to save the pixel of coordinates (t0,t1) to output
	mul	$t8,	$t0,	3
	sb	$s4,	outBuf($t8)
	addiu	$t8, 	$t8,	1
	sb	$s5,	outBuf($t8)
	addiu	$t8, 	$t8,	1
	sb	$s6,	outBuf($t8)

filter_next_pixel_x:
	addiu	$t0,	$t0,	1	# increment X coordinate of filtered pixels
	blt	$t0,	$s0,	min_X_c	# if X < width then calculate maxXc and minXc, zero out max colors, Y coord stay the same
	li	$t7,	0		# temporary variable for add_pad loop
	lw	$t9,	padding		# load size of padding to $t9
add_pad:
	beq	$t7,	$t9,	filter_next_pixel_y
	addiu	$t7,	$t7,	1
	addiu	$t8, 	$t8,	1	# increment address
	sb	$zero,	outBuf($t8)
	j	add_pad			# repeat loop

filter_next_pixel_y:
	# load filtered line to output buffer
	li	$v0,	15
	lw	$a0,	idOutput
	la	$a1,	outBuf
	mul	$a2,	$s0,	3	# 3 * width
	addu	$a2,	$a2,	$t9	# add padding to total length of line
	syscall
	bltz	$v0,	quit		# error

	# move to next row
	addiu	$t1,	$t1,	1	# increment Y coordinate of filtered pixels
	beq	$t1,	$s1,	quit	# end the program if its Y is now maximal (==height)
	li	$t0,	0		# we start in the beginning of new line
	ble	$t1,	$s7,	min_Y_c	# don't load any new next lines into the buf
	addiu	$t8,	$s3,	1
	beq	$t8,	$s1,	min_Y_c	

# load new line to input buffer
	# calculate place for new line in input buffer
	div	$t4,	$s2
	mfhi	$t8
	mul	$t8,	$t8,	$s0
	mul	$t8,	$t8,	3

	# reading new line from file
	lw 	$a0,	idInput
	li	$v0,	14
	la	$a1,	buf($t8)
	mul	$a2,	$s0,	3	# 3 * width
	syscall
	mul 	$t7,	$s0,	3	# temporary variable to check correctness of syscall
	bne	$v0,	$t7,	quit	# error
	addiu	$s3,	$s3,	1	# increment index of top row in input buffer

	li	$v0,	14		# read padding
	la	$a1,	pad
	move	$a2,	$t9
	syscall
	bne	$v0,	$t9,	quit	# error

	j	min_Y_c			# start filtering new line

quit:
#close_out:
	li	$v0,	16		# close outfile
	lw	$a0,	idOutput
	syscall
close_in:
	li	$v0,	16		# close infile
	lw	$a0,	idInput
	syscall
#exit:
	li	$v0,	10		# exit
	syscall

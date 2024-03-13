declare i8 @llvm.abs.i8 ( i8 , i1 )
declare i16 @llvm.abs.i16 ( i16 , i1 )
declare i32 @llvm.abs.i32 ( i32 , i1 )
declare i64 @llvm.abs.i64 ( i64 , i1 )
declare i8 @llvm.vector.reduce.smin.v32i8(<32 x i8>)

declare void @llvm.memset.p0.i32 ( i8*, i8,  i32 , i1 )
declare void @llvm.memset.p0.i64 ( i8*, i8,  i64 , i1 )

declare void @llvm.memmove.p0.p0.i32 ( i8*, i8*,  i32 , i1 )
declare void @llvm.memmove.p0.p0.i64 ( i8*, i8*,  i64 , i1 )

declare void @llvm.memcpy.p0.p0.i32 ( i8*, i8*,  i32 , i1 )
declare void @llvm.memcpy.p0.p0.i64 ( i8*, i8*,  i64 , i1 )

declare float @llvm.fabs.float ( float  )
declare double @llvm.fabs.double ( double  )

declare float @llvm.sqrt.float ( float  )
declare double @llvm.sqrt.double ( double  )

declare float @llvm.sin.float ( float  )
declare double @llvm.sin.double ( double  )

declare float @llvm.cos.float ( float  )
declare double @llvm.cos.double ( double  )

declare float @llvm.trunc.float ( float  )
declare double @llvm.trunc.double ( double  )

declare float @llvm.round.float ( float  )
declare double @llvm.round.double ( double  )

declare float @llvm.floor.float ( float  )
declare double @llvm.floor.double ( double  )

declare float @llvm.ceil.float ( float  )
declare double @llvm.ceil.double ( double  )

define i1 @FORT_equ_i8 ( i8 %x, i8 %y ) #0 {
%r = icmp eq i8 %x, %y
ret i1 %r
}

define i1 @FORT_equ_i16 ( i16 %x, i16 %y ) #0 {
%r = icmp eq i16 %x, %y
ret i1 %r
}

define i1 @FORT_equ_i32 ( i32 %x, i32 %y ) #0 {
%r = icmp eq i32 %x, %y
ret i1 %r
}

define i1 @FORT_equ_i64 ( i64 %x, i64 %y ) #0 {
%r = icmp eq i64 %x, %y
ret i1 %r
}

define i1 @FORT_equ_ptr ( ptr %x, ptr %y ) #0 {
%r = icmp eq ptr %x, %y
ret i1 %r
}


define i1 @FORT_equ_float ( float %x, float %y ) #0 {
%r = fcmp ueq float %x, %y
ret i1 %r
}

define i1 @FORT_equ_double ( double %x, double %y ) #0 {
%r = fcmp ueq double %x, %y
ret i1 %r
}


define i1 @FORT_neq_i8 ( i8 %x, i8 %y ) #0 {
%r = icmp ne i8 %x, %y
ret i1 %r
}

define i1 @FORT_neq_i16 ( i16 %x, i16 %y ) #0 {
%r = icmp ne i16 %x, %y
ret i1 %r
}

define i1 @FORT_neq_i32 ( i32 %x, i32 %y ) #0 {
%r = icmp ne i32 %x, %y
ret i1 %r
}

define i1 @FORT_neq_i64 ( i64 %x, i64 %y ) #0 {
%r = icmp ne i64 %x, %y
ret i1 %r
}

define i1 @FORT_neq_ptr ( ptr %x, ptr %y ) #0 {
%r = icmp ne ptr %x, %y
ret i1 %r
}


define i1 @FORT_neq_float ( float %x, float %y ) #0 {
%r = fcmp une float %x, %y
ret i1 %r
}

define i1 @FORT_neq_double ( double %x, double %y ) #0 {
%r = fcmp une double %x, %y
ret i1 %r
}


define i1 @FORT_gt_float ( float %x, float %y ) #0 {
%r = fcmp ugt float %x, %y
ret i1 %r
}

define i1 @FORT_gt_double ( double %x, double %y ) #0 {
%r = fcmp ugt double %x, %y
ret i1 %r
}


define i1 @FORT_gt_i8 ( i8 %x, i8 %y ) #0 {
%r = icmp sgt i8 %x, %y
ret i1 %r
}

define i1 @FORT_gt_i16 ( i16 %x, i16 %y ) #0 {
%r = icmp sgt i16 %x, %y
ret i1 %r
}

define i1 @FORT_gt_i32 ( i32 %x, i32 %y ) #0 {
%r = icmp sgt i32 %x, %y
ret i1 %r
}

define i1 @FORT_gt_i64 ( i64 %x, i64 %y ) #0 {
%r = icmp sgt i64 %x, %y
ret i1 %r
}


define i1 @FORT_gt_u8 ( i8 %x, i8 %y ) #0 {
%r = icmp ugt i8 %x, %y
ret i1 %r
}

define i1 @FORT_gt_u16 ( i16 %x, i16 %y ) #0 {
%r = icmp ugt i16 %x, %y
ret i1 %r
}

define i1 @FORT_gt_u32 ( i32 %x, i32 %y ) #0 {
%r = icmp ugt i32 %x, %y
ret i1 %r
}

define i1 @FORT_gt_u64 ( i64 %x, i64 %y ) #0 {
%r = icmp ugt i64 %x, %y
ret i1 %r
}

define i1 @FORT_gt_ptr ( ptr %x, ptr %y ) #0 {
%r = icmp ugt ptr %x, %y
ret i1 %r
}


define i1 @FORT_lt_float ( float %x, float %y ) #0 {
%r = fcmp ult float %x, %y
ret i1 %r
}

define i1 @FORT_lt_double ( double %x, double %y ) #0 {
%r = fcmp ult double %x, %y
ret i1 %r
}


define i1 @FORT_lt_i8 ( i8 %x, i8 %y ) #0 {
%r = icmp slt i8 %x, %y
ret i1 %r
}

define i1 @FORT_lt_i16 ( i16 %x, i16 %y ) #0 {
%r = icmp slt i16 %x, %y
ret i1 %r
}

define i1 @FORT_lt_i32 ( i32 %x, i32 %y ) #0 {
%r = icmp slt i32 %x, %y
ret i1 %r
}

define i1 @FORT_lt_i64 ( i64 %x, i64 %y ) #0 {
%r = icmp slt i64 %x, %y
ret i1 %r
}


define i1 @FORT_lt_u8 ( i8 %x, i8 %y ) #0 {
%r = icmp ult i8 %x, %y
ret i1 %r
}

define i1 @FORT_lt_u16 ( i16 %x, i16 %y ) #0 {
%r = icmp ult i16 %x, %y
ret i1 %r
}

define i1 @FORT_lt_u32 ( i32 %x, i32 %y ) #0 {
%r = icmp ult i32 %x, %y
ret i1 %r
}

define i1 @FORT_lt_u64 ( i64 %x, i64 %y ) #0 {
%r = icmp ult i64 %x, %y
ret i1 %r
}

define i1 @FORT_lt_ptr ( ptr %x, ptr %y ) #0 {
%r = icmp ult ptr %x, %y
ret i1 %r
}


define i1 @FORT_gte_float ( float %x, float %y ) #0 {
%r = fcmp uge float %x, %y
ret i1 %r
}

define i1 @FORT_gte_double ( double %x, double %y ) #0 {
%r = fcmp uge double %x, %y
ret i1 %r
}


define i1 @FORT_gte_i8 ( i8 %x, i8 %y ) #0 {
%r = icmp sge i8 %x, %y
ret i1 %r
}

define i1 @FORT_gte_i16 ( i16 %x, i16 %y ) #0 {
%r = icmp sge i16 %x, %y
ret i1 %r
}

define i1 @FORT_gte_i32 ( i32 %x, i32 %y ) #0 {
%r = icmp sge i32 %x, %y
ret i1 %r
}

define i1 @FORT_gte_i64 ( i64 %x, i64 %y ) #0 {
%r = icmp sge i64 %x, %y
ret i1 %r
}


define i1 @FORT_gte_u8 ( i8 %x, i8 %y ) #0 {
%r = icmp uge i8 %x, %y
ret i1 %r
}

define i1 @FORT_gte_u16 ( i16 %x, i16 %y ) #0 {
%r = icmp uge i16 %x, %y
ret i1 %r
}

define i1 @FORT_gte_u32 ( i32 %x, i32 %y ) #0 {
%r = icmp uge i32 %x, %y
ret i1 %r
}

define i1 @FORT_gte_u64 ( i64 %x, i64 %y ) #0 {
%r = icmp uge i64 %x, %y
ret i1 %r
}

define i1 @FORT_gte_ptr ( ptr %x, ptr %y ) #0 {
%r = icmp uge ptr %x, %y
ret i1 %r
}


define i1 @FORT_lte_float ( float %x, float %y ) #0 {
%r = fcmp ule float %x, %y
ret i1 %r
}

define i1 @FORT_lte_double ( double %x, double %y ) #0 {
%r = fcmp ule double %x, %y
ret i1 %r
}


define i1 @FORT_lte_i8 ( i8 %x, i8 %y ) #0 {
%r = icmp sle i8 %x, %y
ret i1 %r
}

define i1 @FORT_lte_i16 ( i16 %x, i16 %y ) #0 {
%r = icmp sle i16 %x, %y
ret i1 %r
}

define i1 @FORT_lte_i32 ( i32 %x, i32 %y ) #0 {
%r = icmp sle i32 %x, %y
ret i1 %r
}

define i1 @FORT_lte_i64 ( i64 %x, i64 %y ) #0 {
%r = icmp sle i64 %x, %y
ret i1 %r
}


define i1 @FORT_lte_u8 ( i8 %x, i8 %y ) #0 {
%r = icmp ule i8 %x, %y
ret i1 %r
}

define i1 @FORT_lte_u16 ( i16 %x, i16 %y ) #0 {
%r = icmp ule i16 %x, %y
ret i1 %r
}

define i1 @FORT_lte_u32 ( i32 %x, i32 %y ) #0 {
%r = icmp ule i32 %x, %y
ret i1 %r
}

define i1 @FORT_lte_u64 ( i64 %x, i64 %y ) #0 {
%r = icmp ule i64 %x, %y
ret i1 %r
}

define i1 @FORT_lte_ptr ( ptr %x, ptr %y ) #0 {
%r = icmp ule ptr %x, %y
ret i1 %r
}


define float @FORT_add_float ( float %x, float %y ) #0 {
%r = fadd float %x, %y
ret float %r
}

define double @FORT_add_double ( double %x, double %y ) #0 {
%r = fadd double %x, %y
ret double %r
}


define i8 @FORT_add_i8 ( i8 %x, i8 %y ) #0 {
%r = add i8 %x, %y
ret i8 %r
}

define i16 @FORT_add_i16 ( i16 %x, i16 %y ) #0 {
%r = add i16 %x, %y
ret i16 %r
}

define i32 @FORT_add_i32 ( i32 %x, i32 %y ) #0 {
%r = add i32 %x, %y
ret i32 %r
}

define i64 @FORT_add_i64 ( i64 %x, i64 %y ) #0 {
%r = add i64 %x, %y
ret i64 %r
}


define float @FORT_sub_float ( float %x, float %y ) #0 {
%r = fsub float %x, %y
ret float %r
}

define double @FORT_sub_double ( double %x, double %y ) #0 {
%r = fsub double %x, %y
ret double %r
}


define i8 @FORT_sub_i8 ( i8 %x, i8 %y ) #0 {
%r = sub i8 %x, %y
ret i8 %r
}

define i16 @FORT_sub_i16 ( i16 %x, i16 %y ) #0 {
%r = sub i16 %x, %y
ret i16 %r
}

define i32 @FORT_sub_i32 ( i32 %x, i32 %y ) #0 {
%r = sub i32 %x, %y
ret i32 %r
}

define i64 @FORT_sub_i64 ( i64 %x, i64 %y ) #0 {
%r = sub i64 %x, %y
ret i64 %r
}


define float @FORT_mul_float ( float %x, float %y ) #0 {
%r = fmul float %x, %y
ret float %r
}

define double @FORT_mul_double ( double %x, double %y ) #0 {
%r = fmul double %x, %y
ret double %r
}


define i8 @FORT_mul_i8 ( i8 %x, i8 %y ) #0 {
%r = mul i8 %x, %y
ret i8 %r
}

define i16 @FORT_mul_i16 ( i16 %x, i16 %y ) #0 {
%r = mul i16 %x, %y
ret i16 %r
}

define i32 @FORT_mul_i32 ( i32 %x, i32 %y ) #0 {
%r = mul i32 %x, %y
ret i32 %r
}

define i64 @FORT_mul_i64 ( i64 %x, i64 %y ) #0 {
%r = mul i64 %x, %y
ret i64 %r
}


define float @FORT_div_float ( float %x, float %y ) #0 {
%r = fdiv float %x, %y
ret float %r
}

define double @FORT_div_double ( double %x, double %y ) #0 {
%r = fdiv double %x, %y
ret double %r
}


define i8 @FORT_div_i8 ( i8 %x, i8 %y ) #0 {
%r = sdiv i8 %x, %y
ret i8 %r
}

define i16 @FORT_div_i16 ( i16 %x, i16 %y ) #0 {
%r = sdiv i16 %x, %y
ret i16 %r
}

define i32 @FORT_div_i32 ( i32 %x, i32 %y ) #0 {
%r = sdiv i32 %x, %y
ret i32 %r
}

define i64 @FORT_div_i64 ( i64 %x, i64 %y ) #0 {
%r = sdiv i64 %x, %y
ret i64 %r
}


define i8 @FORT_div_u8 ( i8 %x, i8 %y ) #0 {
%r = udiv i8 %x, %y
ret i8 %r
}

define i16 @FORT_div_u16 ( i16 %x, i16 %y ) #0 {
%r = udiv i16 %x, %y
ret i16 %r
}

define i32 @FORT_div_u32 ( i32 %x, i32 %y ) #0 {
%r = udiv i32 %x, %y
ret i32 %r
}

define i64 @FORT_div_u64 ( i64 %x, i64 %y ) #0 {
%r = udiv i64 %x, %y
ret i64 %r
}


define float @FORT_rem_float ( float %x, float %y ) #0 {
%r = frem float %x, %y
ret float %r
}

define double @FORT_rem_double ( double %x, double %y ) #0 {
%r = frem double %x, %y
ret double %r
}


define i8 @FORT_rem_i8 ( i8 %x, i8 %y ) #0 {
%r = srem i8 %x, %y
ret i8 %r
}

define i16 @FORT_rem_i16 ( i16 %x, i16 %y ) #0 {
%r = srem i16 %x, %y
ret i16 %r
}

define i32 @FORT_rem_i32 ( i32 %x, i32 %y ) #0 {
%r = srem i32 %x, %y
ret i32 %r
}

define i64 @FORT_rem_i64 ( i64 %x, i64 %y ) #0 {
%r = srem i64 %x, %y
ret i64 %r
}


define i8 @FORT_rem_u8 ( i8 %x, i8 %y ) #0 {
%r = urem i8 %x, %y
ret i8 %r
}

define i16 @FORT_rem_u16 ( i16 %x, i16 %y ) #0 {
%r = urem i16 %x, %y
ret i16 %r
}

define i32 @FORT_rem_u32 ( i32 %x, i32 %y ) #0 {
%r = urem i32 %x, %y
ret i32 %r
}

define i64 @FORT_rem_u64 ( i64 %x, i64 %y ) #0 {
%r = urem i64 %x, %y
ret i64 %r
}


define i8 @FORT_shl_i8 ( i8 %x, i8 %y ) #0 {
%r = shl i8 %x, %y
ret i8 %r
}

define i16 @FORT_shl_i16 ( i16 %x, i16 %y ) #0 {
%r = shl i16 %x, %y
ret i16 %r
}

define i32 @FORT_shl_i32 ( i32 %x, i32 %y ) #0 {
%r = shl i32 %x, %y
ret i32 %r
}

define i64 @FORT_shl_i64 ( i64 %x, i64 %y ) #0 {
%r = shl i64 %x, %y
ret i64 %r
}


define i8 @FORT_shr_i8 ( i8 %x, i8 %y ) #0 {
%r = ashr i8 %x, %y
ret i8 %r
}

define i16 @FORT_shr_i16 ( i16 %x, i16 %y ) #0 {
%r = ashr i16 %x, %y
ret i16 %r
}

define i32 @FORT_shr_i32 ( i32 %x, i32 %y ) #0 {
%r = ashr i32 %x, %y
ret i32 %r
}

define i64 @FORT_shr_i64 ( i64 %x, i64 %y ) #0 {
%r = ashr i64 %x, %y
ret i64 %r
}


define i8 @FORT_shr_u8 ( i8 %x, i8 %y ) #0 {
%r = lshr i8 %x, %y
ret i8 %r
}

define i16 @FORT_shr_u16 ( i16 %x, i16 %y ) #0 {
%r = lshr i16 %x, %y
ret i16 %r
}

define i32 @FORT_shr_u32 ( i32 %x, i32 %y ) #0 {
%r = lshr i32 %x, %y
ret i32 %r
}

define i64 @FORT_shr_u64 ( i64 %x, i64 %y ) #0 {
%r = lshr i64 %x, %y
ret i64 %r
}


define i8 @FORT_or_i8 ( i8 %x, i8 %y ) #0 {
%r = or i8 %x, %y
ret i8 %r
}

define i16 @FORT_or_i16 ( i16 %x, i16 %y ) #0 {
%r = or i16 %x, %y
ret i16 %r
}

define i32 @FORT_or_i32 ( i32 %x, i32 %y ) #0 {
%r = or i32 %x, %y
ret i32 %r
}

define i64 @FORT_or_i64 ( i64 %x, i64 %y ) #0 {
%r = or i64 %x, %y
ret i64 %r
}


define i8 @FORT_and_i8 ( i8 %x, i8 %y ) #0 {
%r = and i8 %x, %y
ret i8 %r
}

define i16 @FORT_and_i16 ( i16 %x, i16 %y ) #0 {
%r = and i16 %x, %y
ret i16 %r
}

define i32 @FORT_and_i32 ( i32 %x, i32 %y ) #0 {
%r = and i32 %x, %y
ret i32 %r
}

define i64 @FORT_and_i64 ( i64 %x, i64 %y ) #0 {
%r = and i64 %x, %y
ret i64 %r
}


define i8 @FORT_xor_i8 ( i8 %x, i8 %y ) #0 {
%r = xor i8 %x, %y
ret i8 %r
}

define i16 @FORT_xor_i16 ( i16 %x, i16 %y ) #0 {
%r = xor i16 %x, %y
ret i16 %r
}

define i32 @FORT_xor_i32 ( i32 %x, i32 %y ) #0 {
%r = xor i32 %x, %y
ret i32 %r
}

define i64 @FORT_xor_i64 ( i64 %x, i64 %y ) #0 {
%r = xor i64 %x, %y
ret i64 %r
}


define i8 @FORT_fromto_float_u8 ( float %x ) #0 {
%r = fptoui float %x to i8
ret i8 %r
}

define i16 @FORT_fromto_float_u16 ( float %x ) #0 {
%r = fptoui float %x to i16
ret i16 %r
}

define i32 @FORT_fromto_float_u32 ( float %x ) #0 {
%r = fptoui float %x to i32
ret i32 %r
}

define i64 @FORT_fromto_float_u64 ( float %x ) #0 {
%r = fptoui float %x to i64
ret i64 %r
}

define i8 @FORT_fromto_double_u8 ( double %x ) #0 {
%r = fptoui double %x to i8
ret i8 %r
}

define i16 @FORT_fromto_double_u16 ( double %x ) #0 {
%r = fptoui double %x to i16
ret i16 %r
}

define i32 @FORT_fromto_double_u32 ( double %x ) #0 {
%r = fptoui double %x to i32
ret i32 %r
}

define i64 @FORT_fromto_double_u64 ( double %x ) #0 {
%r = fptoui double %x to i64
ret i64 %r
}


define i8 @FORT_fromto_float_i8 ( float %x ) #0 {
%r = fptosi float %x to i8
ret i8 %r
}

define i16 @FORT_fromto_float_i16 ( float %x ) #0 {
%r = fptosi float %x to i16
ret i16 %r
}

define i32 @FORT_fromto_float_i32 ( float %x ) #0 {
%r = fptosi float %x to i32
ret i32 %r
}

define i64 @FORT_fromto_float_i64 ( float %x ) #0 {
%r = fptosi float %x to i64
ret i64 %r
}

define i8 @FORT_fromto_double_i8 ( double %x ) #0 {
%r = fptosi double %x to i8
ret i8 %r
}

define i16 @FORT_fromto_double_i16 ( double %x ) #0 {
%r = fptosi double %x to i16
ret i16 %r
}

define i32 @FORT_fromto_double_i32 ( double %x ) #0 {
%r = fptosi double %x to i32
ret i32 %r
}

define i64 @FORT_fromto_double_i64 ( double %x ) #0 {
%r = fptosi double %x to i64
ret i64 %r
}


define float @FORT_fromto_u8_float ( i8 %x ) #0 {
%r = uitofp i8 %x to float
ret float %r
}

define double @FORT_fromto_u8_double ( i8 %x ) #0 {
%r = uitofp i8 %x to double
ret double %r
}

define float @FORT_fromto_u16_float ( i16 %x ) #0 {
%r = uitofp i16 %x to float
ret float %r
}

define double @FORT_fromto_u16_double ( i16 %x ) #0 {
%r = uitofp i16 %x to double
ret double %r
}

define float @FORT_fromto_u32_float ( i32 %x ) #0 {
%r = uitofp i32 %x to float
ret float %r
}

define double @FORT_fromto_u32_double ( i32 %x ) #0 {
%r = uitofp i32 %x to double
ret double %r
}

define float @FORT_fromto_u64_float ( i64 %x ) #0 {
%r = uitofp i64 %x to float
ret float %r
}

define double @FORT_fromto_u64_double ( i64 %x ) #0 {
%r = uitofp i64 %x to double
ret double %r
}


define float @FORT_fromto_i8_float ( i8 %x ) #0 {
%r = sitofp i8 %x to float
ret float %r
}

define double @FORT_fromto_i8_double ( i8 %x ) #0 {
%r = sitofp i8 %x to double
ret double %r
}

define float @FORT_fromto_i16_float ( i16 %x ) #0 {
%r = sitofp i16 %x to float
ret float %r
}

define double @FORT_fromto_i16_double ( i16 %x ) #0 {
%r = sitofp i16 %x to double
ret double %r
}

define float @FORT_fromto_i32_float ( i32 %x ) #0 {
%r = sitofp i32 %x to float
ret float %r
}

define double @FORT_fromto_i32_double ( i32 %x ) #0 {
%r = sitofp i32 %x to double
ret double %r
}

define float @FORT_fromto_i64_float ( i64 %x ) #0 {
%r = sitofp i64 %x to float
ret float %r
}

define double @FORT_fromto_i64_double ( i64 %x ) #0 {
%r = sitofp i64 %x to double
ret double %r
}


define i8 @FORT_fromto_ptr_i8 ( ptr %x ) #0 {
%r = ptrtoint ptr %x to i8
ret i8 %r
}

define i16 @FORT_fromto_ptr_i16 ( ptr %x ) #0 {
%r = ptrtoint ptr %x to i16
ret i16 %r
}

define i32 @FORT_fromto_ptr_i32 ( ptr %x ) #0 {
%r = ptrtoint ptr %x to i32
ret i32 %r
}

define i64 @FORT_fromto_ptr_i64 ( ptr %x ) #0 {
%r = ptrtoint ptr %x to i64
ret i64 %r
}


define ptr @FORT_fromto_i8_ptr ( i8 %x ) #0 {
%r = inttoptr i8 %x to ptr
ret ptr %r
}

define ptr @FORT_fromto_i16_ptr ( i16 %x ) #0 {
%r = inttoptr i16 %x to ptr
ret ptr %r
}

define ptr @FORT_fromto_i32_ptr ( i32 %x ) #0 {
%r = inttoptr i32 %x to ptr
ret ptr %r
}

define ptr @FORT_fromto_i64_ptr ( i64 %x ) #0 {
%r = inttoptr i64 %x to ptr
ret ptr %r
}


define float @FORT_truncto_double_float ( double %x ) #0 {
%r = fptrunc double %x to float
ret float %r
}


define i1 @FORT_truncto_i64_i1 ( i64 %x ) #0 {
%r = trunc i64 %x to i1
ret i1 %r
}

define i1 @FORT_truncto_i32_i1 ( i32 %x ) #0 {
%r = trunc i32 %x to i1
ret i1 %r
}

define i1 @FORT_truncto_i16_i1 ( i16 %x ) #0 {
%r = trunc i16 %x to i1
ret i1 %r
}

define i1 @FORT_truncto_i8_i1 ( i8 %x ) #0 {
%r = trunc i8 %x to i1
ret i1 %r
}


define i8 @FORT_truncto_i64_i8 ( i64 %x ) #0 {
%r = trunc i64 %x to i8
ret i8 %r
}

define i8 @FORT_truncto_i32_i8 ( i32 %x ) #0 {
%r = trunc i32 %x to i8
ret i8 %r
}

define i8 @FORT_truncto_i16_i8 ( i16 %x ) #0 {
%r = trunc i16 %x to i8
ret i8 %r
}


define i16 @FORT_truncto_i64_i16 ( i64 %x ) #0 {
%r = trunc i64 %x to i16
ret i16 %r
}

define i16 @FORT_truncto_i32_i16 ( i32 %x ) #0 {
%r = trunc i32 %x to i16
ret i16 %r
}


define i32 @FORT_truncto_i64_i32 ( i64 %x ) #0 {
%r = trunc i64 %x to i32
ret i32 %r
}


define double @FORT_extto_float_double ( float %x ) #0 {
%r = fpext float %x to double
ret double %r
}


define i64 @FORT_extto_i8_i64 ( i8 %x ) #0 {
%r = sext i8 %x to i64
ret i64 %r
}

define i32 @FORT_extto_i8_i32 ( i8 %x ) #0 {
%r = sext i8 %x to i32
ret i32 %r
}

define i16 @FORT_extto_i8_i16 ( i8 %x ) #0 {
%r = sext i8 %x to i16
ret i16 %r
}


define i64 @FORT_extto_i16_i64 ( i16 %x ) #0 {
%r = sext i16 %x to i64
ret i64 %r
}

define i32 @FORT_extto_i16_i32 ( i16 %x ) #0 {
%r = sext i16 %x to i32
ret i32 %r
}


define i64 @FORT_extto_i32_i64 ( i32 %x ) #0 {
%r = sext i32 %x to i64
ret i64 %r
}


define i64 @FORT_extto_u8_i64 ( i8 %x ) #0 {
%r = sext i8 %x to i64
ret i64 %r
}

define i32 @FORT_extto_u8_i32 ( i8 %x ) #0 {
%r = sext i8 %x to i32
ret i32 %r
}

define i16 @FORT_extto_u8_i16 ( i8 %x ) #0 {
%r = sext i8 %x to i16
ret i16 %r
}


define i64 @FORT_extto_u16_i64 ( i16 %x ) #0 {
%r = sext i16 %x to i64
ret i64 %r
}

define i32 @FORT_extto_u16_i32 ( i16 %x ) #0 {
%r = sext i16 %x to i32
ret i32 %r
}


define i64 @FORT_extto_u32_i64 ( i32 %x ) #0 {
%r = sext i32 %x to i64
ret i64 %r
}


define i64 @FORT_extto_u8_u64 ( i8 %x ) #0 {
%r = zext i8 %x to i64
ret i64 %r
}

define i32 @FORT_extto_u8_u32 ( i8 %x ) #0 {
%r = zext i8 %x to i32
ret i32 %r
}

define i16 @FORT_extto_u8_u16 ( i8 %x ) #0 {
%r = zext i8 %x to i16
ret i16 %r
}


define i64 @FORT_extto_u16_u64 ( i16 %x ) #0 {
%r = zext i16 %x to i64
ret i64 %r
}

define i32 @FORT_extto_u16_u32 ( i16 %x ) #0 {
%r = zext i16 %x to i32
ret i32 %r
}


define i64 @FORT_extto_u32_u64 ( i32 %x ) #0 {
%r = zext i32 %x to i64
ret i64 %r
}


define i64 @FORT_extto_i1_i64 ( i1 %x ) #0 {
%r = zext i1 %x to i64
ret i64 %r
}

define i32 @FORT_extto_i1_i32 ( i1 %x ) #0 {
%r = zext i1 %x to i32
ret i32 %r
}

define i16 @FORT_extto_i1_i16 ( i1 %x ) #0 {
%r = zext i1 %x to i16
ret i16 %r
}

define i8 @FORT_extto_i1_i8 ( i1 %x ) #0 {
%r = zext i1 %x to i8
ret i8 %r
}


define i64 @FORT_extto_i1_u64 ( i1 %x ) #0 {
%r = zext i1 %x to i64
ret i64 %r
}

define i32 @FORT_extto_i1_u32 ( i1 %x ) #0 {
%r = zext i1 %x to i32
ret i32 %r
}

define i16 @FORT_extto_i1_u16 ( i1 %x ) #0 {
%r = zext i1 %x to i16
ret i16 %r
}

define i8 @FORT_extto_i1_u8 ( i1 %x ) #0 {
%r = zext i1 %x to i8
ret i8 %r
}


define i64 @FORT_extto_i8_u64 ( i8 %x ) #0 {
%r = zext i8 %x to i64
ret i64 %r
}

define i32 @FORT_extto_i8_u32 ( i8 %x ) #0 {
%r = zext i8 %x to i32
ret i32 %r
}

define i16 @FORT_extto_i8_u16 ( i8 %x ) #0 {
%r = zext i8 %x to i16
ret i16 %r
}


define i64 @FORT_extto_i16_u64 ( i16 %x ) #0 {
%r = zext i16 %x to i64
ret i64 %r
}

define i32 @FORT_extto_i16_u32 ( i16 %x ) #0 {
%r = zext i16 %x to i32
ret i32 %r
}


define i64 @FORT_extto_i32_u64 ( i32 %x ) #0 {
%r = zext i32 %x to i64
ret i64 %r
}


define i8 @FORT_bitcast_i8_i8 ( i8 %x ) #0 {
%r = bitcast i8 %x to i8
ret i8 %r
}

define i16 @FORT_bitcast_i16_i16 ( i16 %x ) #0 {
%r = bitcast i16 %x to i16
ret i16 %r
}

define i32 @FORT_bitcast_i32_i32 ( i32 %x ) #0 {
%r = bitcast i32 %x to i32
ret i32 %r
}

define i64 @FORT_bitcast_i64_i64 ( i64 %x ) #0 {
%r = bitcast i64 %x to i64
ret i64 %r
}

define ptr @FORT_bitcast_ptr_ptr ( ptr %x ) #0 {
%r = bitcast ptr %x to ptr
ret ptr %r
}


define float @FORT_neg_float ( float %x ) #0 {
%r = fneg float %x
ret float %r
}

define double @FORT_neg_double ( double %x ) #0 {
%r = fneg double %x
ret double %r
}


define void @FORT_store_i1 ( i1 %x, ptr %y ) #0 {
store i1 %x, ptr %y
ret void
}

define void @FORT_store_i8 ( i8 %x, ptr %y ) #0 {
store i8 %x, ptr %y
ret void
}

define void @FORT_store_i16 ( i16 %x, ptr %y ) #0 {
store i16 %x, ptr %y
ret void
}

define void @FORT_store_i32 ( i32 %x, ptr %y ) #0 {
store i32 %x, ptr %y
ret void
}

define void @FORT_store_i64 ( i64 %x, ptr %y ) #0 {
store i64 %x, ptr %y
ret void
}

define void @FORT_store_float ( float %x, ptr %y ) #0 {
store float %x, ptr %y
ret void
}

define void @FORT_store_double ( double %x, ptr %y ) #0 {
store double %x, ptr %y
ret void
}

define void @FORT_store_ptr ( ptr %x, ptr %y ) #0 {
store ptr %x, ptr %y
ret void
}


define i1 @FORT_load_i1 ( ptr %x ) #0 {
%r = load i1 , i1* %x
ret i1 %r
}

define i8 @FORT_load_i8 ( ptr %x ) #0 {
%r = load i8 , i8* %x
ret i8 %r
}

define i16 @FORT_load_i16 ( ptr %x ) #0 {
%r = load i16 , i16* %x
ret i16 %r
}

define i32 @FORT_load_i32 ( ptr %x ) #0 {
%r = load i32 , i32* %x
ret i32 %r
}

define i64 @FORT_load_i64 ( ptr %x ) #0 {
%r = load i64 , i64* %x
ret i64 %r
}

define float @FORT_load_float ( ptr %x ) #0 {
%r = load float , float* %x
ret float %r
}

define double @FORT_load_double ( ptr %x ) #0 {
%r = load double , double* %x
ret double %r
}

define ptr @FORT_load_ptr ( ptr %x ) #0 {
%r = load ptr , ptr %x
ret ptr %r
}


define ptr @FORT_index_i1_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr i1 , i1* %p , i8 %i
ret i1* %r
}

define ptr @FORT_index_i1_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr i1 , i1* %p , i16 %i
ret i1* %r
}

define ptr @FORT_index_i1_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr i1 , i1* %p , i32 %i
ret i1* %r
}

define ptr @FORT_index_i1_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr i1 , i1* %p , i64 %i
ret i1* %r
}

define ptr @FORT_index_i8_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr i8 , i8* %p , i8 %i
ret i8* %r
}

define ptr @FORT_index_i8_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr i8 , i8* %p , i16 %i
ret i8* %r
}

define ptr @FORT_index_i8_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr i8 , i8* %p , i32 %i
ret i8* %r
}

define ptr @FORT_index_i8_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr i8 , i8* %p , i64 %i
ret i8* %r
}

define ptr @FORT_index_i16_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr i16 , i16* %p , i8 %i
ret i16* %r
}

define ptr @FORT_index_i16_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr i16 , i16* %p , i16 %i
ret i16* %r
}

define ptr @FORT_index_i16_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr i16 , i16* %p , i32 %i
ret i16* %r
}

define ptr @FORT_index_i16_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr i16 , i16* %p , i64 %i
ret i16* %r
}

define ptr @FORT_index_i32_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr i32 , i32* %p , i8 %i
ret i32* %r
}

define ptr @FORT_index_i32_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr i32 , i32* %p , i16 %i
ret i32* %r
}

define ptr @FORT_index_i32_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr i32 , i32* %p , i32 %i
ret i32* %r
}

define ptr @FORT_index_i32_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr i32 , i32* %p , i64 %i
ret i32* %r
}

define ptr @FORT_index_i64_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr i64 , i64* %p , i8 %i
ret i64* %r
}

define ptr @FORT_index_i64_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr i64 , i64* %p , i16 %i
ret i64* %r
}

define ptr @FORT_index_i64_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr i64 , i64* %p , i32 %i
ret i64* %r
}

define ptr @FORT_index_i64_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr i64 , i64* %p , i64 %i
ret i64* %r
}

define ptr @FORT_index_float_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr float , float* %p , i8 %i
ret float* %r
}

define ptr @FORT_index_float_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr float , float* %p , i16 %i
ret float* %r
}

define ptr @FORT_index_float_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr float , float* %p , i32 %i
ret float* %r
}

define ptr @FORT_index_float_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr float , float* %p , i64 %i
ret float* %r
}

define ptr @FORT_index_double_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr double , double* %p , i8 %i
ret double* %r
}

define ptr @FORT_index_double_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr double , double* %p , i16 %i
ret double* %r
}

define ptr @FORT_index_double_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr double , double* %p , i32 %i
ret double* %r
}

define ptr @FORT_index_double_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr double , double* %p , i64 %i
ret double* %r
}

define ptr @FORT_index_ptr_i8 ( ptr %p, i8 %i ) #0 {
%r = getelementptr ptr , ptr %p , i8 %i
ret ptr %r
}

define ptr @FORT_index_ptr_i16 ( ptr %p, i16 %i ) #0 {
%r = getelementptr ptr , ptr %p , i16 %i
ret ptr %r
}

define ptr @FORT_index_ptr_i32 ( ptr %p, i32 %i ) #0 {
%r = getelementptr ptr , ptr %p , i32 %i
ret ptr %r
}

define ptr @FORT_index_ptr_i64 ( ptr %p, i64 %i ) #0 {
%r = getelementptr ptr , ptr %p , i64 %i
ret ptr %r
}


define i8 @FORT_abs_i8 ( i8 %x ) #0 {
%r = call i8 @llvm.abs.i8 ( i8 %x , i1 1 )
ret i8 %r
}

define i16 @FORT_abs_i16 ( i16 %x ) #0 {
%r = call i16 @llvm.abs.i16 ( i16 %x , i1 1 )
ret i16 %r
}

define i32 @FORT_abs_i32 ( i32 %x ) #0 {
%r = call i32 @llvm.abs.i32 ( i32 %x , i1 1 )
ret i32 %r
}

define i64 @FORT_abs_i64 ( i64 %x ) #0 {
%r = call i64 @llvm.abs.i64 ( i64 %x , i1 1 )
ret i64 %r
}


define float @FORT_abs_float ( float %x ) #0 {
%r = call float @llvm.fabs.float ( float %x )
ret float %r
}

define double @FORT_abs_double ( double %x ) #0 {
%r = call double @llvm.fabs.double ( double %x )
ret double %r
}


define float @FORT_sqrt_float ( float %x ) #0 {
%r = call float @llvm.sqrt.float ( float %x )
ret float %r
}

define double @FORT_sqrt_double ( double %x ) #0 {
%r = call double @llvm.sqrt.double ( double %x )
ret double %r
}


define float @FORT_sin_float ( float %x ) #0 {
%r = call float @llvm.sin.float ( float %x )
ret float %r
}

define double @FORT_sin_double ( double %x ) #0 {
%r = call double @llvm.sin.double ( double %x )
ret double %r
}


define float @FORT_cos_float ( float %x ) #0 {
%r = call float @llvm.cos.float ( float %x )
ret float %r
}

define double @FORT_cos_double ( double %x ) #0 {
%r = call double @llvm.cos.double ( double %x )
ret double %r
}


define float @FORT_trunc_float ( float %x ) #0 {
%r = call float @llvm.trunc.float ( float %x )
ret float %r
}

define double @FORT_trunc_double ( double %x ) #0 {
%r = call double @llvm.trunc.double ( double %x )
ret double %r
}


define float @FORT_round_float ( float %x ) #0 {
%r = call float @llvm.round.float ( float %x )
ret float %r
}

define double @FORT_round_double ( double %x ) #0 {
%r = call double @llvm.round.double ( double %x )
ret double %r
}


define float @FORT_floor_float ( float %x ) #0 {
%r = call float @llvm.floor.float ( float %x )
ret float %r
}

define double @FORT_floor_double ( double %x ) #0 {
%r = call double @llvm.floor.double ( double %x )
ret double %r
}


define float @FORT_ceil_float ( float %x ) #0 {
%r = call float @llvm.ceil.float ( float %x )
ret float %r
}

define double @FORT_ceil_double ( double %x ) #0 {
%r = call double @llvm.ceil.double ( double %x )
ret double %r
}


define void @FORT_memset_i32 (i8* %p, i8 %c, i32 %n ) #0 {
call void @llvm.memset.p0.i32 ( i8* %p, i8 %c,  i32 %n ,i1 0 )
ret void
}

define void @FORT_memset_i64 (i8* %p, i8 %c, i64 %n ) #0 {
call void @llvm.memset.p0.i64 ( i8* %p, i8 %c,  i64 %n ,i1 0 )
ret void
}


define void @FORT_memmove_i32 (i8* %p, i8* %q, i32 %n ) #0 {
call void @llvm.memmove.p0.p0.i32 ( i8* %p, i8* %q,  i32 %n ,i1 0 )
ret void
}

define void @FORT_memmove_i64 (i8* %p, i8* %q, i64 %n ) #0 {
call void @llvm.memmove.p0.p0.i64 ( i8* %p, i8* %q,  i64 %n ,i1 0 )
ret void
}


define void @FORT_memcpy_i32 (i8* %p, i8* %q, i32 %n ) #0 {
call void @llvm.memcpy.p0.p0.i32 ( i8* %p, i8* %q,  i32 %n ,i1 0 )
ret void
}

define void @FORT_memcpy_i64 (i8* %p, i8* %q, i64 %n ) #0 {
call void @llvm.memcpy.p0.p0.i64 ( i8* %p, i8* %q,  i64 %n ,i1 0 )
ret void
}

define <32 x i8> @FORT_load_v32_i8(ptr %p) #0
{
	%r = load <32 x i8>, <32 x i8>* %p
	ret <32 x i8> %r
}

define <32 x i8> @FORT_insert_element_v32_i8(<32 x i8> %v, i32 %i, i8 %x) #0 
{
  %r = insertelement <32 x i8> %v, i8 %x, i32 %i
  ret <32 x i8> %r
}

define <32 x i8> @FORT_select_v32_i8(<32 x i8> %a, <32 x i8> %x, <32 x i8> %y) #0 {
  %z = trunc <32 x i8> %a to <32 x i1>
  %r = select <32 x i1> %z, <32 x i8> %x, <32 x i8> %y
  ret <32 x i8> %r
}

define <32 x i8> @FORT_equ_v32_i8(<32 x i8> %x, <32 x i8> %y) #0 {
  %r = icmp eq <32 x i8> %x, %y

  %rr = sext <32 x i1> %r to <32 x i8>

  ret <32 x i8> %rr
}

define i8 @FORT_reduce_min_v32_i8(<32 x i8> %x) #0 {
  %r = call i8 @llvm.vector.reduce.smin.v32i8(<32 x i8> %x)
  ret i8 %r
  }


attributes #0 = { alwaysinline }

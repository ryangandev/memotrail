import { z } from 'zod';

export const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, { message: 'Password is required' }),
});

export const SignupSchema = z.object({
  email: z.string().email(),
  password: z
    .string()
    .min(8, { message: 'Password must be at least 8 characters long' })
    .regex(/[a-zA-Z]/, { message: 'Password must include at least one letter' })
    .regex(/[0-9]/, { message: 'Password must include at least one digit' }),
});

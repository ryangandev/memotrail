'use server';

import { LoginSchema, SignupSchema } from '@/schemas/auth-schema';

import { createClient } from '@/lib/supabase/server';
import { createUser } from '@/lib/db/auth';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';

export async function login(loginData: z.infer<typeof LoginSchema>) {
  const parsedData = LoginSchema.safeParse(loginData);

  if (!parsedData.success) {
    return { error: 'Invalid credentials' };
  }

  const supabase = await createClient();

  const { error } = await supabase.auth.signInWithPassword(parsedData.data);

  if (error) {
    return { error: 'Invalid credentials' };
  }

  revalidatePath('/', 'layout');
  redirect('/lessons');
}

export async function signup(signupData: z.infer<typeof SignupSchema>) {
  const parsedData = SignupSchema.safeParse(signupData);

  if (!parsedData.success) {
    return { error: 'Invalid email or password' };
  }

  const supabase = await createClient();

  const { data, error } = await supabase.auth.signUp(parsedData.data);

  if (error) {
    return { error: error.message };
  }

  await createUser(data.user?.id!, data.user?.email!);

  return {
    success: true,
    message: 'Successfully signed up! You can now log in',
  };
}

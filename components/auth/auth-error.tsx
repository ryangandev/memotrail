import { cn } from '@/lib/utils';

export default function AuthError({
  message,
  className,
}: {
  message?: string;
  className?: string;
}) {
  return (
    <>
      {message && (
        <p className={cn('text-destructive text-xs', className)}>{message}</p>
      )}
    </>
  );
}

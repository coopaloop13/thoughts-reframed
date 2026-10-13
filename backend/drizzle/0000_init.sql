CREATE TYPE "public"."session_status" AS ENUM('UPLOADED', 'TRANSCRIBING', 'REFRAMING', 'SYNTHESIZING', 'COMPLETED', 'FAILED');--> statement-breakpoint
CREATE TABLE "sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"status" "session_status" DEFAULT 'UPLOADED' NOT NULL,
	"recording_key" text NOT NULL,
	"transcript" text,
	"reframed_text" text,
	"audio_key" text,
	"error" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"apple_sub" text NOT NULL,
	"voice_profile_id" text,
	"voice_sample_key" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_apple_sub_unique" UNIQUE("apple_sub")
);
--> statement-breakpoint
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
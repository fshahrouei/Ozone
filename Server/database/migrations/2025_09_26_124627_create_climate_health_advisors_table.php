<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateClimateHealthAdvisorsTable extends Migration
{
    public function up()
    {
        Schema::create('climate_health_advisors', function (Blueprint $table) {
            $table->id();

            // Client identity (UUID from Flutter app)
            $table->string('uuid', 100)->nullable();

            // Main form data
            $table->string('name', 190);
            $table->decimal('location_lat', 12, 8)->nullable();
            $table->decimal('location_lon', 12, 8)->nullable();
            $table->enum('sensitivity', ['sensitive', 'normal', 'relaxed'])->default('normal');
            $table->integer('overall_score')->default(0);

            // Flexible arrays and structures
            $table->json('diseases')->nullable(); // Example: ["allergies","asthma",...]
            $table->json('alerts')->nullable();   // Example: {pollution:bool, sound:bool, hours2h:[...]}

            // Metadata received (e.g., NDJSON stream info)
            $table->timestamp('received_at')->nullable();
            $table->string('ip', 45)->nullable();        // IPv4/IPv6
            $table->text('user_agent')->nullable();

            // App / device info
            $table->string('app_version', 190);
            $table->string('platforn', 190);             // ⚠️ Probably a typo → should be "platform"
            $table->string('fcm_token', 255);
            $table->timestamp('last_notification_at')->nullable();

            $table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('climate_health_advisors');
    }
}

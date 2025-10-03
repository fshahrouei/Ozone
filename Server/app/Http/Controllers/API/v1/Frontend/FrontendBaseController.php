<?php

namespace App\Http\Controllers\API\V1\Frontend;

use App;
use App\Http\Controllers\Helper\GeneralController;
use Illuminate\Http\Request;


class FrontendBaseController extends GeneralController
{
    protected $var = [];

    public function __construct()
    {
        $this->var['model_framework'] = 'bs5';
        $this->var['model_table'] = true;
        $this->var['model_lang'] = App::getLocale();
        $this->var['short_site_name'] =  setting($this->var['model_lang'] . "_meta_short_site_name") ?? setting("fa_meta_short_site_name");
        $this->var['model_dir'] =  'rtl';
        if (App::getLocale() == 'en') {
            $this->var['model_dir'] =  'ltr';
        }
        $this->var['model_theme'] =  'light';
    }


    public function index(Request $request)
    {

        // Example: https://dinamit.ir/api/v1/frontend/posts/index
        foreach ($this->var as $key => $value) {
            $$key = $value;
        }


        if ($model_api == 'planets') {
            $category_id = 391;
        } else {
            $category_id = 131;
        }

        // dd($model_api, $category_id);

        $$model_name = $model_class::whereCategoryId($category_id)->select($model_index_fields)->get()->map(function ($item) use ($model_index_fields) {
            $data = [];
            foreach ($model_index_fields as $field) {
                if ($field === 'thumbnail') {
                    $data['imageUrl'] = ($item->thumbnail['512x512-webp'] ?? null) ? url($item->thumbnail['512x512-webp']) : null;
                } else {
                    $data[$field] = $item->$field;
                }
            }
            return $data;
        });



        // dd($posts);
        return response()->json([
            'succeed' => true,
            'status' => 200,
            'message' => 'Operation completed successfully.',
            'data' => $$model_name,
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }

    public function show(Request $request, $id)
    {
        foreach ($this->var as $key => $value) {
            $$key = $value;
        }

        // Find item by id (or by slug if you want to change later)
        $item = $model_class::where('id', $id)->select($model_show_fields)->first();

        if (!$item) {
            return response()->json([
                'succeed' => false,
                'status' => 404,
                'message' => 'Item not found.',
                'data' => null,
            ], 404, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
        }

        $data = [];
        foreach ($model_show_fields as $field) {
            if ($field === 'thumbnail') {
                $data['imageUrl'] = ($item->thumbnail['512x512-webp'] ?? null) ? url($item->thumbnail['512x512-webp']) : null;
            } elseif ($field === 'name') {
                $data[$field] = $item->$field;
            } elseif ($field === 'body') {
                $markdown = null;
                foreach ($item->$field ?? [] as $body) {
                    if ($body['type'] == 'markdown') $markdown = $body['markdown'] ?? null;
                }
                $data['markdown'] = $markdown;
            } elseif ($field === 'attributes') {

                $newAttributes = [];
                foreach ($item->$field ?? [] as $key => $attribute) {
                    $newAttributes[] = [
                        "name" => $attribute['name'],
                        "value" => $attribute['value']
                    ];
                }

                $data['attributes']  = $newAttributes;
            } else {
                $data[$field] = $item->$field;
            }
        }

        $data['video'] = 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4';

        // $data['attributes'] = [
        //     ['name' => 'Diameter', 'value' => '116,460 km'],
        //     ['name' => 'Mass', 'value' => '5.683 × 10^26 kg'],
        //     ['name' => 'Distance from Sun', 'value' => '1.434 billion km'],
        //     ['name' => 'Number of Moons', 'value' => '82'],
        //     ['name' => 'Temperature', 'value' => '-178°C'],
        // ];

        // $data['text'] = "# Saturn
        //
        // Saturn is the sixth planet from the Sun and the second-largest in our Solar System.
        //
        // ## Main Features
        //
        // - **Spectacular ring system** made of ice and rock
        // - Over *82 known moons*, including Titan
        // - Very low density (it would float in water!)
        // - Famous hexagonal storm at the north pole
        //
        // > Saturn’s beauty and mysteries make it a favorite target for scientists and sky-watchers alike.
        // ";

        return response()->json([
            'succeed' => true,
            'status' => 200,
            'message' => 'Operation completed successfully.',
            'data' => $data,
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }
}
